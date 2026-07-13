/* Baked-in ASan defaults for the fuzz binary (Mayhem owns ASAN_OPTIONS at run
 * time, so runtime env overrides are not used).
 *
 * detect_leaks=0: pdfalto is an allocate-and-exit batch converter (upstream is
 * still chasing leaks, e.g. kermitt2/pdfalto#231); LeakSanitizer would flag
 * ~every input and drown real memory-safety defects. ASan + UBSan themselves
 * stay ON and halting. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
