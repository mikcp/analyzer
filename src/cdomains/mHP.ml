include Printable.Std

module TID = ThreadIdDomain.FlagConfiguredTID

type t = {
  tid: ThreadIdDomain.ThreadLifted.t;
  created: ConcDomain.ThreadSet.t;
  must_joined: ConcDomain.ThreadSet.t;
} [@@deriving eq, ord]

let hash {tid; created; must_joined} =
  13 * ThreadIdDomain.ThreadLifted.hash tid + 7 * ConcDomain.ThreadSet.hash created + ConcDomain.ThreadSet.hash must_joined

let pretty () {tid; created; must_joined} =
  Pretty.dprintf "{ tid=%a; created=%a; must_joined=%a }" ThreadIdDomain.ThreadLifted.pretty tid ConcDomain.ThreadSet.pretty created ConcDomain.ThreadSet.pretty must_joined

include Printable.SimplePretty (
  struct
    type nonrec t = t
    let pretty = pretty
  end
  )

(** Can it be excluded that the thread tid2 is running at a program point where  *)
(*  thread tid1 has created the threads in created1 *)
let definitely_not_started (current, created) other =
  if (not (TID.is_must_parent current other)) then
    false
  else
    let ident_or_may_be_created creator = TID.equal creator other || TID.may_create creator other in
    if ConcDomain.ThreadSet.is_top created then
      false
    else
      not @@ ConcDomain.ThreadSet.exists (ident_or_may_be_created) created

(** Must the thread with thread id other be already joined  *)
let must_be_joined other joined =
  if ConcDomain.ThreadSet.is_top joined then
    false
  else
    List.mem other (ConcDomain.ThreadSet.elements joined)

(** May two program points with respective MHP information happen in parallel *)
let may_happen_in_parallel one two =
  let {tid=tid; created=created; must_joined=must_joined} = one in
  let {tid=tid2; created=created2; must_joined=must_joined2} = two in
  match tid,tid2 with
  | `Lifted tid, `Lifted tid2 ->
    if (TID.is_unique tid) && (TID.equal tid tid2) then
      false
    else if definitely_not_started (tid,created) tid2 || definitely_not_started (tid2,created2) tid then
      false
    else if must_be_joined tid2 must_joined || must_be_joined tid must_joined2 then
      false
    else
      true
  | _ -> true
