// PARAM: --disable sem.assert.refine
#include <assert.h>

int main() {
  while (1)
    assert(0); // FAIL!
  return 0;
}
