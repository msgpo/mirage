open Astring
open Functoria
open Mirage_impl_misc
open Action.Infix
module Log = Mirage_impl_misc.Log
module Key = Mirage_key

let solo5_manifest_path = Fpath.v "_build/manifest.json"

let clean_manifest () = Action.rm solo5_manifest_path

let generate_manifest_json () =
  Log.info (fun m -> m "generating manifest");
  let networks =
    List.map (fun n -> (n, `Network)) !Mirage_impl_network.all_networks
  in
  let blocks =
    Hashtbl.fold
      (fun k _v acc -> (k, `Block) :: acc)
      Mirage_impl_block.all_blocks []
  in
  let to_string (name, typ) =
    Fmt.strf {json|{ "name": %S, "type": %S }|json} name
      (match typ with `Network -> "NET_BASIC" | `Block -> "BLOCK_BASIC")
  in
  let devices = List.map to_string (networks @ blocks) in
  let s = String.concat ~sep:", " devices in
  Action.with_output ~path:solo5_manifest_path
    ~purpose:"Solo5 application manifest file" (fun fmt ->
      Fmt.pf fmt
        {|{
  "type": "solo5.manifest",
  "version": 1,
  "devices": [ %s ]
}
|}
        s)

let generate_manifest_c () =
  let json = solo5_manifest_path in
  let c = "_build/manifest.c" in
  let cmd =
    Bos.Cmd.(v "solo5-elftool" % "gen-manifest" % Fpath.to_string json % c)
  in
  Action.mkdir Fpath.(v "_build") >>= fun _created ->
  Log.info (fun m -> m "executing %a" Bos.Cmd.pp cmd);
  Action.run_cmd cmd

let solo5_pkg = function
  | `Virtio -> ("solo5-bindings-virtio", ".virtio")
  | `Muen -> ("solo5-bindings-muen", ".muen")
  | `Hvt -> ("solo5-bindings-hvt", ".hvt")
  | `Genode -> ("solo5-bindings-genode", ".genode")
  | `Spt -> ("solo5-bindings-spt", ".spt")
  | _ -> invalid_arg "solo5 bindings only defined for solo5 targets"

let cflags pkg = pkg_config pkg [ "--cflags" ]

let compile_manifest target =
  let pkg, _post = solo5_pkg target in
  let c = "_build/manifest.c" in
  let obj = "_build/manifest.o" in
  cflags pkg >>= fun cflags ->
  let cmd = Bos.Cmd.(v "cc" %% of_list cflags % "-c" % c % "-o" % obj) in
  Log.info (fun m -> m "executing %a" Bos.Cmd.pp cmd);
  Action.run_cmd cmd

let files i =
  let ctx = Info.context i in
  let target = Key.(get ctx target) in
  Fpath.v "_build/manifest.json"
  :: (match target with `Virtio -> [ Fpath.v "libvirt.xml" ] | _ -> [])
