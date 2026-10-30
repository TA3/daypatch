// Adds an LC_LOAD_WEAK_DYLIB command to a thin arm64 Mach-O executable, so the
// app loads daypatch.dylib by itself (no DYLD_INSERT_LIBRARIES, no
// allow-dyld-environment-variables entitlement). Weak: if the dylib is missing
// the app still launches, unpatched.
//
//   insert-dylib <executable> <install path, e.g. @executable_path/../Frameworks/daypatch.dylib>
//
// The executable must be unsigned first (codesign --remove-signature) and is
// re-signed afterwards. Same logic as PatchEngine.insertLoadCommand in the companion.
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s <executable> <dylib install path>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "r+b");
    if (!f) { perror(argv[1]); return 1; }
    struct mach_header_64 h;
    if (fread(&h, sizeof h, 1, f) != 1 || h.magic != MH_MAGIC_64) { fprintf(stderr, "not a thin 64-bit Mach-O\n"); return 1; }

    // Read the existing load commands: refuse if already present or still signed,
    // and find where the first section's data starts (the end of free header space).
    char *cmds = malloc(h.sizeofcmds);
    if (fread(cmds, h.sizeofcmds, 1, f) != 1) { fprintf(stderr, "short read\n"); return 1; }
    uint64_t firstData = UINT64_MAX;
    const char *path = argv[2];
    for (uint32_t i = 0, off = 0; i < h.ncmds; i++) {
        struct load_command *lc = (struct load_command *)(cmds + off);
        if (lc->cmd == LC_CODE_SIGNATURE) { fprintf(stderr, "remove the code signature first\n"); return 1; }
        if (lc->cmd == LC_LOAD_DYLIB || lc->cmd == LC_LOAD_WEAK_DYLIB) {
            struct dylib_command *d = (struct dylib_command *)lc;
            if (strcmp((char *)lc + d->dylib.name.offset, path) == 0) { printf("already present\n"); return 0; }
        }
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            struct section_64 *sec = (struct section_64 *)(seg + 1);
            for (uint32_t s = 0; s < seg->nsects; s++)
                if (sec[s].offset && sec[s].offset < firstData) firstData = sec[s].offset;
        }
        off += lc->cmdsize;
    }

    uint32_t size = (uint32_t)((sizeof(struct dylib_command) + strlen(path) + 1 + 7) & ~7u);
    uint64_t end = sizeof h + h.sizeofcmds;
    if (end + size > firstData) { fprintf(stderr, "not enough header space (%llu free, %u needed)\n", firstData - end, size); return 1; }

    char *cmd = calloc(1, size);
    struct dylib_command *d = (struct dylib_command *)cmd;
    d->cmd = LC_LOAD_WEAK_DYLIB;
    d->cmdsize = size;
    d->dylib.name.offset = sizeof(struct dylib_command);
    d->dylib.timestamp = 2;
    d->dylib.current_version = 0x10000;
    d->dylib.compatibility_version = 0x10000;
    strcpy(cmd + sizeof(struct dylib_command), path);

    fseek(f, (long)end, SEEK_SET);
    fwrite(cmd, size, 1, f);
    h.ncmds += 1;
    h.sizeofcmds += size;
    fseek(f, 0, SEEK_SET);
    fwrite(&h, sizeof h, 1, f);
    fclose(f);
    printf("added LC_LOAD_WEAK_DYLIB %s\n", path);
    return 0;
}
