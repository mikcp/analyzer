// SKIP PARAM: --set solver td3 --enable ana.int.interval  --enable ana.base.partition-arrays.enabled  --set ana.activated "['base','threadid','threadflag','expRelation','mallocWrapper','apron']" --set ana.base.privatization none --set ana.apron.privatization dummy
// Example from https://www-apr.lip6.fr/~mine/publi/article-mine-HOSC06.pdf
void main(void) {
  int X = 0;
  int N = rand();
  if(N < 0) { N = 0; }

  while(X < N) {
    X++;
  }

  assert(X-N == 0);
  assert(X == N);

  if(X == N) {
    N = 8;
  } else {
    // is dead code but if that is detected or not depends on what we do in branch
    // currently we can't detect this
    N = 42;
  }
}
