open Stdune

let ( ^/ ) = Filename.concat

module Command = struct
  type t = { program : string; args : string list }

  let create program args = { program; args }
  let to_string { program; args } = String.concat ~sep:" " (program :: args)
  let dev_null = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0
  let args_arr { program; args } = Array.of_list (program :: args)

  module Running = struct
    type nonrec t = { pid : int; command : t }

    let wait_exn { pid; command } =
      let got_pid, status = Unix.waitpid [] pid in
      if got_pid <> pid then failwith "wait returned unexpected pid";
      match status with
      | Unix.WEXITED status -> status
      | _ ->
          failwith
            (Printf.sprintf "`%s` unexpected process status" (to_string command))
  end

  let run_background t ~stdio_redirect =
    let stdin, stdout, stderr =
      match stdio_redirect with
      | `This_process -> (Unix.stdin, Unix.stdout, Unix.stderr)
      | `Ignore -> (dev_null, dev_null, dev_null)
      | `Ignore_with_stdout_to file_desc -> (dev_null, file_desc, dev_null)
    in
    let pid = Unix.create_process t.program (args_arr t) stdin stdout stderr in
    { Running.pid; command = t }

  let run_blocking_exn t ~stdio_redirect =
    run_background t ~stdio_redirect |> Running.wait_exn
end

let write_text_file ~path ~contents =
  let out_channel = Out_channel.open_text path in
  Out_channel.output_string out_channel contents;
  Out_channel.close out_channel

let build_dir = "build"

module Package = struct
  type t = { name : string; version : string }

  let list_of_toml toml_table =
    Toml.Types.Table.to_seq toml_table
    |> Seq.map ~f:(fun (name, data) ->
           let name = Toml.Types.Table.Key.to_string name in
           let version =
             match data with
             | Toml.Types.TString version -> version
             | other ->
                 Printf.eprintf
                   "While parsing version of package `%s` expected string but \
                    found `%s`"
                   name
                   (Toml.Printer.string_of_value other);
                 exit 1
           in
           { name; version })
    |> List.of_seq
end

module Bin = struct
  type t = { name : string; src : string }

  let list_of_toml toml_table =
    Toml.Types.Table.to_seq toml_table
    |> Seq.map ~f:(fun (name, data) ->
           let name = Toml.Types.Table.Key.to_string name in
           let src =
             match data with
             | Toml.Types.TString src -> src
             | other ->
                 Printf.eprintf
                   "While parsing src of bin `%s` expected string but found \
                    `%s`"
                   name
                   (Toml.Printer.string_of_value other);
                 exit 1
           in
           { name; src })
    |> List.of_seq

  let dune_file t ~package_dependencies =
    let libraries =
      List.map package_dependencies ~f:(fun { Package.name; _ } -> name)
      |> String.concat ~sep:" "
    in
    let lines =
      [
        "(executable";
        Printf.sprintf " (public_name %s)" t.name;
        " (name main)";
        Printf.sprintf " (libraries %s))" libraries;
      ]
    in
    String.concat ~sep:"\n" lines

  let make_dune_directory t ~root ~package_build_dir ~package_dependencies =
    let source_dir_path = root ^/ t.src in
    let bin_dir_path = package_build_dir ^/ "bin" in
    let this_bin_dir_path = bin_dir_path ^/ t.name in
    FileUtil.mkdir ~parent:true bin_dir_path;
    FileUtil.cp ~recurse:true [ source_dir_path ] this_bin_dir_path;
    write_text_file
      ~path:(this_bin_dir_path ^/ "dune")
      ~contents:(dune_file t ~package_dependencies)
end

module Manifest = struct
  type t = {
    name : string;
    synopsis : string option;
    homepage : string option;
    license : string option;
    authors : string list option;
    bug_reports : string option;
    maintainer : string list option;
    dependencies : Package.t list;
    bins : Bin.t list;
  }

  let all_keys = [ "package"; "dependencies"; "bins" ]

  let all_package_keys =
    [
      "name";
      "synopsis";
      "homepage";
      "license";
      "authors";
      "bug_reports";
      "maintainer";
      "dependencies";
    ]

  let validate_table_keys table expected_keys =
    let expected_keys = String.Set.of_list expected_keys in
    let key_strings =
      Toml.Types.Table.to_seq table
      |> Seq.map ~f:(fun (key, _) -> Toml.Types.Table.Key.to_string key)
      |> List.of_seq
    in
    match
      List.find key_strings ~f:(fun key_string ->
          not (String.Set.mem expected_keys key_string))
    with
    | None -> Ok ()
    | Some key_string -> Error (`Unexpected_key key_string)

  let of_toml toml_table =
    (match validate_table_keys toml_table all_keys with
    | Ok () -> ()
    | Error (`Unexpected_key key_string) ->
        Printf.eprintf "Unexpected field in manifest: %s" key_string;
        exit 1);
    let package_table =
      match Toml.Lenses.(get toml_table (key "package" |-- table)) with
      | Some table -> table
      | None ->
          Printf.eprintf "Manifest is missing table field `package`";
          exit 1
    in
    (match validate_table_keys package_table all_package_keys with
    | Ok () -> ()
    | Error (`Unexpected_key key_string) ->
        Printf.eprintf "Unexpected field in `package` table of manifest: %s"
          key_string;
        exit 1);
    let package_get_string_opt key_ =
      Toml.Lenses.(get package_table (key key_ |-- string))
    in
    let package_get_string_list_opt key_ =
      Toml.Lenses.(get package_table (key key_ |-- array))
      |> Option.map ~f:(function
           | Toml.Types.NodeEmpty -> []
           | Toml.Types.NodeString xs -> xs
           | other ->
               Printf.eprintf "%s must be a list of strings (got %s)" key_
                 (Toml.Printer.string_of_array other);
               exit 1)
    in
    let name =
      match package_get_string_opt "name" with
      | Some name -> name
      | None ->
          Printf.eprintf "`package` table in manifest is missing field `name`";
          exit 1
    in
    let synopsis = package_get_string_opt "synopsis" in
    let homepage = package_get_string_opt "homepage" in
    let license = package_get_string_opt "license" in
    let authors = package_get_string_list_opt "authors" in
    let bug_reports = package_get_string_opt "bug_reports" in
    let maintainer = package_get_string_list_opt "maintainer" in
    let dependencies_table =
      match Toml.Lenses.(get toml_table (key "dependencies" |-- table)) with
      | Some table -> table
      | None ->
          Printf.eprintf "Manifest is missing table field `dependencies`";
          exit 1
    in
    let dependencies = Package.list_of_toml dependencies_table in
    let bins_table =
      match Toml.Lenses.(get toml_table (key "bins" |-- table)) with
      | Some table -> table
      | None ->
          Printf.eprintf "Manifest is missing table field `bins`";
          exit 1
    in
    let bins = Bin.list_of_toml bins_table in
    {
      name;
      synopsis;
      homepage;
      license;
      authors;
      bug_reports;
      maintainer;
      dependencies;
      bins;
    }

  let parse ~root =
    let manifest_table =
      Toml.Parser.(from_filename (root ^/ "spice.toml") |> unsafe)
    in
    of_toml manifest_table

  let dune_project t =
    let open Printf in
    let open Option.O in
    let quote = sprintf "\"%s\"" in
    let depends =
      List.map t.dependencies ~f:(fun { Package.name; version } ->
          sprintf "  (%s (= %s))" name version)
      |> String.concat ~sep:"\n"
    in
    let parts =
      [
        Some "(lang dune 3.0)";
        Some "(generate_opam_files true)";
        t.homepage >>| quote >>| sprintf "(homepage %s)";
        t.license >>| quote >>| sprintf "(license %s)";
        t.authors >>| List.map ~f:quote >>| String.concat ~sep:" "
        >>| sprintf "(authors %s)";
        t.maintainer >>| List.map ~f:quote >>| String.concat ~sep:" "
        >>| sprintf "(maintainers %s)";
        t.bug_reports >>| quote >>| sprintf "(bug_reports %s)";
        Some "(package";
        Some (sprintf " (name %s)" t.name);
        t.synopsis >>| quote >>| sprintf " (synopsis %s)";
        Some " (depends";
        Some depends;
        Some " ))";
      ]
    in
    String.concat ~sep:"\n" (List.filter_opt parts)

  let make_empty_build_dir ~root =
    let build_dir_path = root ^/ build_dir in
    if Sys.file_exists build_dir_path then
      if Sys.is_directory build_dir_path then
        FileUtil.rm ~force:Force ~recurse:true [ build_dir_path ]
      else (
        Printf.eprintf "%s exists and is not a directory" build_dir_path;
        exit 1);
    FileUtil.mkdir ~parent:true build_dir_path

  let instantiate t ~root =
    let build_dir_path = root ^/ build_dir in
    make_empty_build_dir ~root;
    let package_dir_path = build_dir_path ^/ t.name in
    FileUtil.mkdir ~parent:true package_dir_path;
    write_text_file
      ~path:(build_dir_path ^/ "dune-project")
      ~contents:(dune_project t);
    List.iter t.bins ~f:(fun bin ->
        Bin.make_dune_directory bin ~root ~package_build_dir:package_dir_path
          ~package_dependencies:t.dependencies)

  let make_merlin_file t ~root =
    let original_working_dir = Unix.getcwd () in
    let build_dir_path = root ^/ build_dir in
    Unix.chdir build_dir_path;
    let build_command =
      Command.create "opam" [ "exec"; "dune"; "--"; "build" ]
    in
    let build_status =
      Command.run_blocking_exn build_command ~stdio_redirect:`Ignore
    in
    if build_status <> 0 then failwith "Unexpected build failure";
    let merlin_file =
      Unix.openfile (root ^/ ".merlin") [ O_CREAT; O_RDWR ] 0o644
    in
    List.iter t.bins ~f:(fun (bin : Bin.t) ->
        let dump_merlin_command =
          Command.create "opam"
            [
              "exec";
              "dune";
              "--";
              "ocaml";
              "dump-dot-merlin";
              t.name ^/ "bin" ^/ bin.name;
            ]
        in
        let dump_merlin_status =
          Command.run_blocking_exn dump_merlin_command
            ~stdio_redirect:(`Ignore_with_stdout_to merlin_file)
        in
        if dump_merlin_status <> 0 then failwith "Unexpected build failure";
        ());
    Unix.close merlin_file;
    Unix.chdir original_working_dir
end

let make_opam_file ~root =
  let build_dir_path = root ^/ build_dir in
  let command =
    Command.create "opam"
      [ "exec"; "dune"; "--"; "build"; "--root"; build_dir_path ]
  in
  (* Note that this command could fail due to missing dependencies but that's
     ok as it will still have the side effect of generating the opam file. *)
  let _status : int =
    Command.run_blocking_exn command ~stdio_redirect:`Ignore
  in
  ()

module Args = struct
  module String_arg_req = struct
    type t = { value : string option ref; opt : string; desc : string }

    let create opt desc = { value = ref None; opt; desc }

    let spec { value; opt; desc } =
      (opt, Arg.String (fun x -> value := Some x), desc)

    let get { value; opt; _ } =
      match !value with
      | Some x -> x
      | None ->
          Printf.eprintf "Missing required argument %s" opt;
          exit 1
  end

  type t = { root : string }

  let parse () =
    let root =
      String_arg_req.create "--root" "path to project root directory"
    in
    let specs = [ String_arg_req.spec root ] in
    let description =
      "Minimal version of spice for building the full version of spice"
    in
    Arg.parse specs
      (fun arg ->
        Printf.eprintf "Unexpected argument: %s" arg;
        exit 1)
      description;
    { root = String_arg_req.get root }
end

let () =
  let { Args.root } = Args.parse () in
  let root =
    if Filename.is_relative root then Unix.getcwd () ^/ root else root
  in
  let manifest = Manifest.parse ~root in
  Manifest.instantiate manifest ~root;
  make_opam_file ~root;
  Manifest.make_merlin_file manifest ~root;
  ()
