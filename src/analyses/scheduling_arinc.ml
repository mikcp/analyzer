(** An analysis specification for didactic purposes. *)
open Prelude.Ana
open Analyses_arinc
open Arinc_schedulabilty_domain
open Arinc_cfg

module Spec : Analyses_arinc.ArincSpec =
struct
  include Analyses_arinc.DefaultSpec

  let name () = "scheduling_arinc"
  module SD = Arinc_schedulabilty_domain.D
  module D = Lattice.Lift(SD)(Printable.DefaultNames)
  module G = Lattice.Unit
  module C = Lattice.Unit

  let numtasks = 2

  (* transfer functions *)
  let assign ctx (lval:lval) (rval:exp) : D.t =
    failwith "lol, wut?!!!"

  let branch ctx (exp:exp) (tv:bool) : D.t =
    failwith "lol, wut?!!!"

  let body ctx (f:fundec) : D.t =
    failwith "lol, wut?!!!"

  let return ctx (exp:exp option) (f:fundec) : D.t =
    failwith "lol, wut?!!!"

  let get_info_for t s =
    List.at t s

  let update_info_for t fn s =
    List.modify_at t fn s

  let get_info_for_leg t (a,b) =
    if t=0 then a else b

  let update_info_for_leg t v (a,b) =
    if t = 0 then (v,b) else (a,v)

  let enter ctx (lval: lval option) (f:varinfo) (args:exp list) : (D.t * D.t) list =
    let t = Times.start_state 2 in
    let state1 = {
      pid = Pid.of_int (Int64.of_int 0);
      priority = Priority.of_int (Int64.of_int 15);
      period = Period.of_int (Int64.of_int 600);
      capacity = Capacity.of_int (Int64.of_int 600);
      processState = PState.ready;
      waitingFor = WaitingForEvent.bot ()
      } in
    let state2 = {
      pid = Pid.of_int (Int64.of_int 1);
      priority = Priority.of_int (Int64.of_int 10);
      period = Period.top ();
      capacity = Capacity.top ();
      processState = PState.ready;
      waitingFor = WaitingForEvent.bot ()
      }
    in
    [ctx.local, `Lifted([state1; state2], t)]

  let combine ctx (lval:lval option) fexp (f:varinfo) (args:exp list) (au:D.t) : D.t =
    failwith "lol, wut?!!!"

  let special ctx (lval: lval option) (f:varinfo) (arglist:exp list) : D.t =
    failwith "lol, wut?!!!"

  (* What if none can run unless time passes? *)
  (* Can ours run relative to other? *)
  let can_run_relative ours other =
    if ours.processState <> PState.ready then
      (* We can not take any actions while not ready *)
      false
    else
      let ours_prio = BatOption.get @@ Priority.to_int ours.priority in
      let other_prio = BatOption.get @@ Priority.to_int other.priority in
      let cmp = Int64.compare ours_prio other_prio in
      if cmp = 0 then
        (* two processes with the same priority *)
        failwith "processes with same prio"
      else if cmp > 0 then
        (* ours > other *)
        true
      else
        (* ours < other *)
        (* we can run if the other is blocked *)
        other.processState <> PState.ready

  let can_run tid taskstates =
    let ours = List.at taskstates tid in
    List.fold_lefti (fun acc i other -> acc && if i=tid then true else can_run_relative ours other) true taskstates

  (* Check if any other task can run relative to t (when assuming that t is not ready) *)
  let any_other_can_run tid taskstates =
    let ours = List.at taskstates tid in
    List.fold_lefti  (fun acc i other -> acc || if i=tid then false else can_run_relative other ours) false taskstates

  (* Get a list of ids of other tasks that are: *)
  (* - waiting on something that can happen without any further computation occuring, i.e.  *)
  (*      - waiting for period                                                              *)
  (*      - end of a timed wait                                                             *)
  (* - NOT waiting for a signal, for the signal to be set, computation needs to be done     *)
  let tasks_waiting_timed_id tid taskstates =
    let t_with_id = List.mapi (fun i x -> (i,x)) taskstates in
    let fn (i,task) = tid <> i && OneTask.is_waiting_for_time_to_pass task in
    let res = List.filter fn t_with_id in
    List.map (fun (i,_) -> i) res

  (* Get the join of all waiting times of tasks in tasks *)
  let get_wait_interval tasks times =
    List.fold_left (fun acc i -> TInterval.join  acc (Times.get_remaining_wait i times)) (TInterval.bot ()) tasks

  (* Can tid be the task that has the shortest wait_time? *)
  let may_be_task_with_min_wait (taskstates, times) tid  =
    let this = List.at taskstates tid in
    let this_wait_time = Times.get_remaining_wait tid times in
    if (not (OneTask.is_waiting_for_time_to_pass this)) then
      (Printf.printf "may be task with min wait for not waiting task";
      false)
    else
      let tasks_with_ids = List.mapi (fun i x -> (i,x)) taskstates in
      let other_waiting_tasks = List.filter (fun (i,x) -> tid <> i && OneTask.is_waiting_for_time_to_pass x) tasks_with_ids in
      (* may t wait for a longer time then tid *)
      let may_wait_longer t =
        let other_wait_time = Times.get_remaining_wait t times in
        TInterval.to_int (TInterval.le this_wait_time other_wait_time) <> Some 0L
      in
      (* if no other tasks are waiting, then this one is the one with the min wait, and fold_left will return true *)
      List.fold_left (fun acc (i,x) -> acc && may_wait_longer i) true other_waiting_tasks

  (* Return taskstate of the task that has the highest priority and is ready to compute *)
  let highest_compute_task (taskstates, times) =
    let ready_tasks = List.filter (fun x -> x.processState = PState.ready) taskstates in
    if List.length ready_tasks = 0 then
      None
    else
      let r = List.reduce (fun acc x -> if Option.get (Priority.to_int acc.priority) < Option.get (Priority.to_int x.priority) then x else acc) ready_tasks in
      Some r

  (* wait and if the wait terminates apply fn, otherwise raise Deadcode *)
  (* this is the common logic of wait_for_endwait and wait_for_period  *)
  let wait_and_do_if_over (taskstates, times) fn tid =
    let waiting_time = Times.get_remaining_wait tid times in
    if TInterval.leq Times.zeroInterval waiting_time then
      (* the waiting time may be zero, we can end waiting *)
      fn (taskstates, times) tid
    else
      (* waiting time is definitely not zero  *)
      if may_be_task_with_min_wait (taskstates, times) tid then
        begin
          let compute_task = highest_compute_task (taskstates, times) in
          match compute_task with
          | Some t ->
            (* t is the highest priority task that has a compute command going on *)
            let other_tid = Int64.to_int @@ Option.get @@ Pid.to_int t.pid in
            let remaining_processing_other = Times.get_remaining_processing other_tid times in
            if TInterval.is_bot remaining_processing_other || TInterval.to_int remaining_processing_other = Some 0L then
              (* if remaining processing time is zero, then the finish computation edge should be taken *)
              raise Deadcode
            else if TInterval.to_int (TInterval.le remaining_processing_other waiting_time) = Some 1L then
              (* if the remaining processing time must be smaller or equal to the wait_time, the finish computation edge should be taken *)
              raise Deadcode
            else
              (* We subtract the waiting_time from the remaining_processing_time of this task to get the new remaining_processing_time *)
              (* To gain precision here, we could encode that computing can not have finished and set the remaining processing time to a minimum of one *)
              (* Also, we could encode that this can only last for however long the minimal wait time actually is *)
              let times = Times.update_remaining_processing other_tid (fun x -> TInterval.meet remaining_processing_other (TInterval.sub_zero_if_neg x waiting_time)) times in
              let times = Times.advance_all_times_by waiting_time times in
              fn (taskstates, times) tid
          | None ->
            (* If no task can compute here, we just simply let time pass *)
            let times = Times.advance_all_times_by waiting_time times in
            fn (taskstates, times) tid
        end
      else
        (* if this may not be the task with the shortest wait_time, this edge should not be taken here *)
        raise Deadcode

  let wait_for_period (taskstates,times) tid =
    let do_restart_period (taskstates, times) tid =
      let times = Times.set_since_period tid Times.zeroInterval times in
      let times = Times.set_remaining_wait tid Times.zeroInterval times in
      let s = update_info_for tid (fun x -> {x with processState = PState.ready}) taskstates in
      s, times
    in
    wait_and_do_if_over (taskstates, times) do_restart_period tid

  let wait_for_endwait (taskstates,times) tid =
    let do_end_wait (s,x) t =
      let times = Times.set_remaining_wait t Times.zeroInterval x in
      let s = update_info_for t (fun x -> {x with processState = PState.ready}) s in
      s, times
    in
    wait_and_do_if_over (taskstates,times) do_end_wait tid


  let finish_computation (taskstates, times) tid =
    (* We can always take this edge, because we never have a lower bound on how long a computation can take      *)
    (* If I am here, the only thing that could interrupt me is a (higher priority) task finishing waiting on sth *)
    (* If the other task wanted to do computation here, we would raise Deadcode even before calling this         *)
    let wcetInterval = Times.get_remaining_processing tid times in
    let possibleInterrupters = tasks_waiting_timed_id tid taskstates in
    if List.length possibleInterrupters == 0 then
      (* This will be not interrupted *)
      let times = Times.set_remaining_processing tid Times.zeroInterval times in
      let times = Times.advance_all_times_by wcetInterval times in
      taskstates, times
    else
      (* As an improvement, we could model here that a "wait" (N/B not a waiting for period) from a lower priority thread will not have any influence here *)
      (* as even when it's wait ends, it will not interrupt this process *)
      let waiting_time_other = get_wait_interval possibleInterrupters times in
      let less_than_waiting_time = TInterval.lt waiting_time_other wcetInterval in
      if not (TInterval.is_bot (TInterval.meet (TInterval.of_int (Int64.of_int 1)) less_than_waiting_time)) then
        (* This is the minimum interval we can compute for sure, so we can subtract this everywhere. If we take less than this time, we can move on *)
        let minimum_definite_compute_interval = TInterval.of_interval (Int64.zero, BatOption.get @@ TInterval.minimal waiting_time_other) in
        let times = Times.set_remaining_processing tid Times.zeroInterval times in
        let times = Times.advance_all_times_by minimum_definite_compute_interval times in
        taskstates, times
      else
      (* We can finish the entire thing, even if it takes WCET *)
      let times = Times.set_remaining_processing tid Times.zeroInterval times in
      let times = Times.advance_all_times_by wcetInterval times in
      taskstates, times


  let start_computation (taskstates, times) tid wcet =
    let wcetInterval = TInterval.of_interval (Int64.zero, Int64.of_int wcet) in
    let times = Times.set_remaining_processing tid wcetInterval times in
    taskstates, times

  let periodic_wait (taskstates, times) tid node =
    (* Check that the deadline is not violated *)
    let time_since_period = Times.get_since_period tid times in
    let deadline  =  BatOption.get @@ Capacity.to_int ((get_info_for taskstates tid).capacity) in
    let deadline_interval = TInterval.of_int deadline in
    (* If time_since_period <=_{must} deadline_interval, the comparison is [0,0], meaning that no deadline was missed *)
    let miss = not (TInterval.to_int (TInterval.gt time_since_period deadline_interval) = Some 0L) in
    (if miss then Printf.printf "%s deadline of t%i was missed: %s > %s (!!!!)\n%s \n\n"
      (Arinc_Node.to_string node)
      tid (TInterval.short 80 time_since_period) (TInterval.short 80 deadline_interval)
      (SD.short 800 (taskstates,times))
      else
      ());
    let period = BatOption.get @@ Period.to_int ((get_info_for taskstates tid).period) in
    let remaining_wait = TInterval.sub (TInterval.of_int period) time_since_period in
    let times = Times.set_remaining_wait tid remaining_wait times in (* set remaining wait time *)
    let s = SD.periodic_wait tid taskstates in
    s, times

  let timed_wait (taskstates, times) tid waittime =
    let remaining_wait = TInterval.of_int (Int64.of_int waittime) in
    let times = Times.set_remaining_wait tid remaining_wait times in (* set remaining wait time *)
    let s = SD.timed_wait tid taskstates in
    s, times

  let arinc_edge_not_bot ((taskstates, times) as state) (tid,e) node =
    if tid = -1 then
      (* This is some special edge e.g. during init *)
      state
    else if e = WaitingForPeriod then
      (* The restart of a period can happen at any time even if the task does not have priority *)
      wait_for_period state tid
    else if e = WaitingForEndWait then
      (* The end of waiting can happen at any time if the task does not have priority *)
      wait_for_endwait state tid
    else if not (can_run tid taskstates) then
      (* all other actions can only happen if this task is in running state, and has the highest priority *)
      raise Deadcode
    else
      match e with
      | SuspendTask i -> SD.suspend i taskstates, times
      | ResumeTask i -> SD.resume i taskstates, times
      | WaitEvent i -> SD.wait_event tid i taskstates, times
      | SetEvent i -> SD.set_event i taskstates, times
      | StartComputation wcet -> start_computation state tid wcet
      | FinishComputation -> finish_computation state tid
      | PeriodicWait -> periodic_wait state tid node
      | TimedWait tw -> timed_wait state tid tw
      | _ -> state

  let arinc_edge ctx (t,e) =
    match ctx.local with
    | `Lifted x -> `Lifted (arinc_edge_not_bot x (t,e) ctx.node)
    | `Top -> `Top
    | `Bot -> `Bot


  let should_join_one a b =
    a.processState = b.processState && a.waitingFor = b.waitingFor

  let should_join a b =
    match a,b with
    | `Lifted (a,x), `Lifted(b, x') ->
      List.fold_left2 (fun x e f -> x && should_join_one e f) true a b
    | _ -> true

  let val_of () = D.bot ()
  let context _ = ()

  let startstate v = D.bot ()
  let otherstate v = D.bot ()
  let exitstate  v = D.bot ()
end

let _ =
  MCP_arinc.register_analysis (module Spec : ArincSpec)
