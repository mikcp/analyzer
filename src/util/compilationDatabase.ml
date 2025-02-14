open Prelude

let basename = "compile_commands.json"

type command_object = {
  directory: string;
  file: string;
  command: string option [@default None];
  arguments: string list option [@default None];
  output: string option [@default None];
} [@@deriving yojson]

type t = command_object list [@@deriving yojson]

let parse_file filename =
  Result.get_ok (of_yojson (Yojson.Safe.from_file filename))

let command_o_regexp = Str.regexp "-o +[^ ]+"
let command_program_regexp = Str.regexp "^ *\\([^ ]+\\)"

let system ~cwd command =
  let old_cwd = Sys.getcwd () in
  Fun.protect ~finally:(fun () ->
      Sys.chdir old_cwd
    ) (fun () ->
      Sys.chdir cwd;
      match Unix.system command with
      | WEXITED 0 -> ()
      | process_status -> failwith (GobUnix.string_of_process_status process_status)
    )

let load_and_preprocess ~all_cppflags filename =
  let database_dir = Filename.dirname (GobFilename.absolute filename) in (* absolute before dirname to avoid . *)
  let reroot =
    let original_path = GobConfig.get_string "exp.compdb.original-path" in
    if original_path <> "" then (
      let original_database_dir = Filename.dirname original_path in
      let old_root = GobFilename.chop_common_suffix database_dir original_database_dir in
      let new_root = GobFilename.chop_common_suffix original_database_dir database_dir in
      if GobConfig.get_bool "dbg.verbose" then
        Printf.printf "Rerooting compilation database\n  from %s\n  to %s\n" old_root new_root;
      Str.global_replace (Str.regexp_string old_root) new_root
    )
    else
      Fun.id
  in
  (* TODO: generalize .goblint for everything *)
  ignore (Goblintutil.create_dir ".goblint");
  let preprocessed_dir = Goblintutil.create_dir (Filename.concat ".goblint" "preprocessed") in
  let preprocess obj =
    let file = obj.file in
    let extension = Filename.extension file in
    if extension = ".s" || extension = ".S" then
      None
    else
      let preprocessed_file = Filename.concat preprocessed_dir (Filename.chop_extension (GobFilename.chop_common_prefix database_dir file) ^ ".i") in
      GobSys.mkdir_parents preprocessed_file;
      let deps_file = Filename.chop_extension preprocessed_file ^ ".d" in
      let preprocess_command = match obj.command, obj.arguments with
        | Some command, None ->
          (* TODO: extract o_file *)
          let command = reroot command in
          let preprocess_command = Str.replace_first command_program_regexp ("\\1 " ^ String.join " " (List.map Filename.quote all_cppflags) ^ " -E -MMD -MT " ^ file) command in
          let preprocess_command = Str.replace_first command_o_regexp ("-o " ^ preprocessed_file) preprocess_command in
          if preprocess_command = command then (* easier way to check if match was found (and replaced) *)
            failwith "CompilationDatabase.preprocess: no -o argument found for " ^ file
          else
            preprocess_command
        | None, Some arguments ->
          let arguments = List.map reroot arguments in
          begin match List.findi (fun i e -> e = "-o") arguments with
            | (o_i, _) ->
              begin match List.split_at o_i arguments with
                | (arguments_program :: arguments_init, _ :: o_file :: arguments_tl) ->
                  let preprocess_arguments = all_cppflags @ "-E" :: "-MMD" :: "-MT" :: file :: arguments_init @ "-o" :: preprocessed_file :: arguments_tl in
                  Filename.quote_command arguments_program preprocess_arguments
                | _ ->
                  failwith "CompilationDatabase.preprocess: no -o argument value found for " ^ file
              end
            | exception Not_found ->
              failwith "CompilationDatabase.preprocess: no -o argument found for " ^ file
          end
        | Some _, Some _ ->
          failwith "CompilationDatabase.preprocess: both command and arguments specified for " ^ file
        | None, None ->
          failwith "CompilationDatabase.preprocess: neither command nor arguments specified for " ^ file
      in
      let cwd = reroot obj.directory in
      if GobConfig.get_bool "dbg.verbose" then
        Printf.printf "Preprocessing %s\n  to %s\n  using %s\n  in %s\n" file preprocessed_file preprocess_command cwd;
      system ~cwd preprocess_command; (* command/arguments might have paths relative to directory *)
      Preprocessor.parse_makefile_deps deps_file;
      Some preprocessed_file
    in
  parse_file filename
  |> BatList.filter_map preprocess
