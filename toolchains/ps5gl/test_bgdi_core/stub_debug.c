/* interpreter.c calls mnemonic_dump() only when the global `debug` verbosity
 * level is > 1, which this boot test never sets. The real implementation
 * lives in core/common/debug.c, but that file also pulls in bgdc.h (the
 * bytecode *compiler*'s own header) for other unrelated content - dragging
 * that in here would mean building compiler internals into the interpreter
 * for a code path that never runs. A no-op stub is all this link needs. */
#include <stdint.h>

void mnemonic_dump( int64_t i, int64_t param ) {
    (void) i;
    (void) param;
}
