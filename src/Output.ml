(* Copyright (c) INRIA and Microsoft Corporation. All rights reserved. *)
(* Licensed under the Apache 2.0 License. *)

(** Decorate each file with a little bit of boilerplate, then print it *)

open Utils
open PPrint

let mk_includes =
  separate_map hardline (fun x -> string "#include " ^^ string x) 

let kremlib_include () =
  if !Options.minimal then
    empty
  else
    mk_includes [ "\"kremlib.h\"" ]

(* A Pprint document with:
 * - #include X for X in the dependencies of the file, followed by
 * - #include Y for each -add-include Y passed on the command-line
 *)
let includes files =
  let extra_includes = mk_includes (List.rev !Options.add_include) in
  let includes = mk_includes (List.rev_map (Printf.sprintf "\"%s.h\"") files) in
  includes ^^ hardline ^^ extra_includes

(* A pair of a header, containing:
 * - the boilerplate specified on the command-line by -header
 * - #include Y for each -add-early-include Y passed on the command-line
 * - #include "kremlib.h"
 * - the #ifndef #define guard,
 * and a footer, containing:
 * - the #endif
 *)
let prefix_suffix name =
  Driver.detect_fstar_if ();
  Driver.detect_kremlin_if ();
  let prefix =
    let header = !Options.header !Driver.fstar_rev !Driver.krml_rev in
    string header ^^ hardline ^^
    mk_includes !Options.add_early_include ^^ hardline ^^
    kremlib_include () ^^
    hardline ^^
    string (Printf.sprintf "#ifndef __%s_H" name) ^^ hardline ^^
    string (Printf.sprintf "#define __%s_H" name) ^^ hardline
  in
  let suffix =
    hardline ^^
    string (Printf.sprintf "#define __%s_H_DEFINED" name) ^^ hardline ^^
    string "#endif"
  in
  prefix, suffix

let in_tmp_dir name =
  Driver.mk_tmpdir_if ();
  let open Driver in
  if !Options.tmpdir <> "" then
    !Options.tmpdir ^^ name
  else
    name

let write_one name prefix program suffix =
  with_open_out_bin (in_tmp_dir name) (fun oc ->
    let doc =
      prefix ^^ hardline ^^ hardline ^^
      separate_map (hardline ^^ hardline) PrintC.p_decl_or_function program ^^
      hardline ^^ suffix ^^ hardline
    in
    PPrint.ToChannel.pretty 0.95 100 oc doc
  )

let write_c files =
  Driver.detect_fstar_if ();
  Driver.detect_kremlin_if ();
  List.fold_left (fun names file ->
    let name, program = file in
    let header = !Options.header !Driver.fstar_rev !Driver.krml_rev in
    let prefix = string (Printf.sprintf "%s\n\n#include \"%s.h\"" header name) in
    let prefix =
      if !Options.add_include_tmh then
        string "#ifdef WPP_CONTROL_GUIDS" ^^ hardline ^^
        string (Printf.sprintf "#include <%s.tmh>" name) ^^ hardline ^^
        string "#endif" ^^ hardline ^^ prefix
      else
        prefix
    in
    write_one (name ^ ".c") prefix program empty;
    name :: names
  ) [] files

let write_h files =
  List.fold_left (fun names file ->
    let name, program = file in
    let prefix, suffix = prefix_suffix name in
    let prefix = prefix ^^ hardline ^^ includes names in
    write_one (name ^ ".h") prefix program suffix;
    name :: names
  ) [] files

let write_makefile custom_c_files c_files h_files =
  let concat_map ext files =
    String.concat " " (List.map (fun f -> f ^ ext) files)
  in
  Utils.with_open_out_bin (in_tmp_dir "Makefile.include") (fun oc ->
    KPrint.bfprintf oc "USER_TARGET=%s\n" !Options.exe_name;
    KPrint.bfprintf oc "USER_CFLAGS=%s\n" (concat_map "" !Options.ccopts);
    KPrint.bfprintf oc "USER_C_FILES=%s\n" (concat_map "" custom_c_files);
    KPrint.bfprintf oc "ALL_C_FILES=%s\n" (concat_map ".c" c_files);
    KPrint.bfprintf oc "ALL_H_FILES=%s\n" (concat_map ".h" h_files)
  );
  Utils.cp Driver.(!Options.tmpdir ^^ "Makefile.basic") Driver.(!misc_dir ^^ "Makefile.basic")
