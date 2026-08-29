extends Node
## ============================================================================
##  SCRAPPY PLAYTEST MULTIPLAYER  --  TEMPORARY, NOT FOR THE GAME JAM BUILD
## ============================================================================
##
##  WHAT IT SYNCS
##    * every player's seagull (position, facing, animation) + a name tag
##    * every player's pet Sean (on/off), so you can see each other's pets
##    * boats: whoever gets in first drives, everyone else can pile on
##    * ocean wave time, so boats sit in the water properly for everyone
##
##  HOW TO USE IT
##    Press F3 in game -> Host, or type an address and Join. The address can be
##    an IP or a hostname (play.example.com), with an optional :port.
##    Also works from the command line:
##      Seagull.exe --mp-host
##      Seagull.exe --mp-join=play.example.com   (or 1.2.3.4, or host:27015)
##      Seagull.exe --mp-name=Jasey
##
##  DEDICATED SERVER (see mp_test/README.md)
##      Seagull.x86_64 --headless --mp-server [--mp-port=27015]
##    Boots res://mp_test/server.tscn instead of the island: no world, just a
##    relay and a referee. One connected player simulates the idle boats.
##
##  ---------------------------------------------------------------------------
##  TO TURN IT OFF : set ENABLED to false (line below). The game then behaves
##                   exactly as it did before -- nothing is touched.
##  TO DELETE IT   : 1. delete the res://mp_test/ folder
##                   2. delete these two lines from project.godot:
##                        [autoload]     MPTest="*res://mp_test/mp_test.gd"
##                        [application]  run/main_scene.dedicated_server=...
##                      Those are the ONLY lines outside this folder -- no
##                      existing game script or scene was modified.
##  ---------------------------------------------------------------------------

const ENABLED := true

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 16
const SEND_HZ := 20.0
const GHOST_LERP := 14.0
const BOAT_LERP := 12.0
const TOGGLE_KEY := KEY_F3
const NAMETAG_SIZE := 0.0006   # bump this if the name tags look too small

const ANIM_NAMES := ["Idle", "Run", "Jump", "Fall", "Glide", "Flap", "Squawk"]
const PLAYER_SCENE_PATH := "res://Player/player.tscn"
const SEAN_SCENE_PATH := "res://sean.tscn"
const SERVER_SCENE_PATH := "res://mp_test/server.tscn"
const NAME_FILE := "user://mp_test_name.txt"

const UI_SCRIPT = preload("res://mp_test/mp_test_ui.gd")

# --- public-ish state, read by the panel ----------------------------------
var player_name := "Gull"
var status := "Offline"
var online := false

## Set by mp_test/server.tscn. A dedicated server has no island of its own, so
## it cannot simulate idle boats or drive the ocean clock - it hands that job
## to a connected player instead (see _world_authority).
var dedicated := false

## Peer that simulates boats nobody is driving, and owns the ocean wave clock.
## On a listen server that is the host (1); on a dedicated server it is the
## lowest-numbered connected player. 0 means nobody is available yet.
var _world_authority := 1

# --- internals ------------------------------------------------------------
var _peer: ENetMultiplayerPeer = null
var _ui: CanvasLayer = null
var _ui_open := false

var _send_accum := 0.0
var _ocean_accum := 0.0

var _level: Node = null
var _local_player: Node = null
var _ghost_root: Node3D = null

var _boats := {}        # boat node name -> boat node
var _boat_owner := {}   # boat node name -> peer id driving it (0 = nobody)
var _boat_net := {}     # boat node name -> {"x": Transform3D, "m": int}
var _aboard := {}       # boat node name -> were we aboard last frame

var _peers := {}        # peer id -> {name, pos, rot, anim, pet}
var _ghosts := {}       # peer id -> {body, sean, label}


func _ready() -> void:
	if not ENABLED:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return

	# keep running (and keep receiving) while the panel pauses the game
	process_mode = Node.PROCESS_MODE_ALWAYS
	# run after everything else, so we can snap the player onto a boat exactly
	# the way boat.gd does in single player
	process_priority = 500
	if "process_physics_priority" in self:
		process_physics_priority = 500

	player_name = _load_name()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	call_deferred("_parse_cmdline")


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
		_peer = null


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			toggle_ui()
			get_viewport().set_input_as_handled()


# ===========================================================================
#  PANEL
# ===========================================================================

func toggle_ui() -> void:
	if _ui_open:
		close_ui()
	else:
		open_ui()


func open_ui() -> void:
	if _ui == null or not is_instance_valid(_ui):
		_ui = CanvasLayer.new()
		_ui.set_script(UI_SCRIPT)
		_ui.name = "MPTestUI"
		get_tree().root.add_child(_ui)
	_ui.visible = true
	_ui.refresh()
	_ui_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.visible = false
	_ui_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if "mouse_locked" in Global:
		Global.mouse_locked = true
	# boat.gd re-asserts this every frame while you are aboard, so this is safe
	if _local_player != null and is_instance_valid(_local_player):
		_local_player.handle_input = true


# ===========================================================================
#  CONNECTING
# ===========================================================================

func host_game(port: int = DEFAULT_PORT) -> void:
	shutdown()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS)
	if err != OK:
		status = "Host failed: %s (is port %d already in use?)" % [error_string(err), port]
		_refresh_ui()
		return
	_peer = p
	multiplayer.multiplayer_peer = p
	online = true
	_pick_world_authority()
	if dedicated:
		status = "Dedicated server listening on port %d" % port
	else:
		status = "Hosting on port %d - give your friends your IP" % port
	_refresh_ui()


func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	shutdown()
	address = address.strip_edges()
	address = address.trim_prefix("http://").trim_prefix("https://").trim_suffix("/")
	if address.contains(":"):
		var bits := address.rsplit(":", true, 1)
		address = bits[0]
		port = int(bits[1])

	# ENet takes hostnames, but resolving here means a bad name fails straight
	# away with a clear message instead of silently timing out
	var ip := address
	if not address.is_valid_ip_address():
		ip = IP.resolve_hostname(address, IP.TYPE_IPV4)
		if ip == "":
			status = "Could not look up '%s' - check the name (and that it has an A record)." % address
			print("[MP] ", status)
			_refresh_ui()
			return

	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		status = "Join failed: %s" % error_string(err)
		_refresh_ui()
		return
	_peer = p
	multiplayer.multiplayer_peer = p
	online = true
	if ip == address:
		status = "Connecting to %s:%d ..." % [address, port]
	else:
		status = "Connecting to %s (%s):%d ..." % [address, ip, port]
	_refresh_ui()


func shutdown() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	online = false

	for id in _ghosts.keys():
		_free_ghost(id)
	_ghosts.clear()
	_peers.clear()
	_boat_owner.clear()
	_boat_net.clear()
	_aboard.clear()
	_world_authority = 1

	# hand every boat back to its own script
	for bname in _boats.keys():
		var b = _boats[bname]
		if is_instance_valid(b):
			b.set_physics_process(true)

	status = "Offline"
	_refresh_ui()


func _on_peer_connected(id: int) -> void:
	if not dedicated:
		_rx_hello.rpc_id(id, player_name)   # a bare server is not a player
	if multiplayer.is_server():
		_rx_owner_table.rpc_id(id, _boat_owner)
		_pick_world_authority()
		_rx_world_authority.rpc_id(id, _world_authority)
	if not dedicated:
		status = "%d gull(s) in the world" % (_peers.size() + 1)
	_refresh_ui()


func _on_peer_disconnected(id: int) -> void:
	if _peers.has(id):   # peer 1 on a dedicated server was never a player
		print("[MP] ", _peers[id].get("name", "Gull %d" % id), " left")
	_free_ghost(id)
	_ghosts.erase(id)
	_peers.erase(id)
	if multiplayer.is_server():
		for bname in _boat_owner.keys():
			if _boat_owner[bname] == id:
				_set_boat_owner(bname, 0)
				_rx_owner.rpc(bname, 0)
		_pick_world_authority()
	_refresh_ui()


## Server only. Decides who simulates the parts of the world nobody owns.
func _pick_world_authority() -> void:
	var was := _world_authority
	if not dedicated:
		_world_authority = 1          # we are playing, so we have the island
	else:
		# peer ids are random, so never re-pick just because a lower one turned
		# up - handing boats over mid-game causes a visible hitch. Only replace
		# the current one once they have actually left.
		var peers := multiplayer.get_peers()
		if _world_authority == 0 or not peers.has(_world_authority):
			_world_authority = peers[0] if peers.size() > 0 else 0
	if _world_authority != was:
		if dedicated and _world_authority != 0:
			print("[MP] idle boats + waves now simulated by peer ", _world_authority)
		_rx_world_authority.rpc(_world_authority)


@rpc("authority", "call_remote", "reliable")
func _rx_world_authority(id: int) -> void:
	_world_authority = id


func _on_connected_to_server() -> void:
	status = "Connected!  (F3 to close this panel)"
	print("[MP] connected as ", player_name)
	_rx_hello.rpc(player_name)
	_refresh_ui()


func _on_connection_failed() -> void:
	print("[MP] connection failed")
	shutdown()
	status = "Connection failed - wrong address, or the port is not open."
	_refresh_ui()


func _on_server_disconnected() -> void:
	shutdown()
	status = "Host closed the game."
	_refresh_ui()


# ===========================================================================
#  PER-FRAME
# ===========================================================================

func _linked() -> bool:
	# true once the handshake is done - sending before that spams RPC errors
	var p := multiplayer.multiplayer_peer
	return online and p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	_refresh_scene_refs()
	if not _linked():
		return
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		_broadcast_state()
	_update_ghosts(delta)
	_sync_ocean(delta)


func _physics_process(delta: float) -> void:
	if _level == null or not _linked():
		return
	var me := multiplayer.get_unique_id()
	for bname in _boats.keys():
		var b = _boats[bname]
		if not is_instance_valid(b):
			continue
		if _driver_of(bname) == me:
			# we are steering: let boat.gd run exactly as it always has
			if not b.is_physics_processing():
				b.set_physics_process(true)
		else:
			# somebody else owns it: freeze its script, follow the wire instead
			if b.is_physics_processing():
				b.set_physics_process(false)
			_follow_remote_boat(b, bname, delta)
		if not _ui_open:
			_check_boarding(b, bname)


func _refresh_scene_refs() -> void:
	var lvl := get_tree().get_first_node_in_group("world")
	if lvl != _level:
		# scene changed (or first frame): everything cached is dead
		_level = lvl
		_ghost_root = null
		_local_player = null
		_boats.clear()
		_boat_net.clear()
		_aboard.clear()
		_ghosts.clear()
		if _level != null:
			for c in _level.get_children():
				if c is CharacterBody3D and ("in_boat" in c) and ("player_offset" in c):
					_boats[String(c.name)] = c
	if _level == null:
		return
	if _local_player == null or not is_instance_valid(_local_player):
		_local_player = get_tree().get_first_node_in_group("player")


# ===========================================================================
#  PLAYERS
# ===========================================================================

func _broadcast_state() -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	var vis: Node3D = _local_player.get_node_or_null("Visuals")
	var rot := vis.rotation if vis != null else Vector3.ZERO

	var anim := 0
	var ap: AnimationPlayer = _local_player.get_node_or_null("Visuals/AnimationPlayer")
	if ap != null:
		anim = maxi(ANIM_NAMES.find(ap.current_animation), 0)

	var pet := false
	if "pet_enabled" in Global:
		pet = Global.pet_enabled

	_rx_state.rpc(_local_player.global_position, rot, anim, pet)

	for bname in _boats.keys():
		if _driver_of(bname) == multiplayer.get_unique_id():
			var b = _boats[bname]
			if is_instance_valid(b):
				_rx_boat.rpc(bname, b.global_transform, int(b.motor))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rx_state(pos: Vector3, rot: Vector3, anim: int, pet: bool) -> void:
	var p := _peer_entry(multiplayer.get_remote_sender_id())
	p["pos"] = pos
	p["rot"] = rot
	p["anim"] = anim
	p["pet"] = pet


@rpc("any_peer", "call_remote", "reliable")
func _rx_hello(who: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var p := _peer_entry(id)
	var was := String(p.get("name", ""))
	p["name"] = who
	if _ghosts.has(id) and is_instance_valid(_ghosts[id]["label"]):
		_ghosts[id]["label"].text = who
	if was != who:   # both sides greet each other, so only announce a change
		print("[MP] ", who, " joined")
	_refresh_ui()


func _peer_entry(id: int) -> Dictionary:
	if not _peers.has(id):
		_peers[id] = {"name": "Gull %d" % id}
	return _peers[id]


func _update_ghosts(delta: float) -> void:
	if _level == null:
		return
	if _ghost_root == null or not is_instance_valid(_ghost_root):
		_ghost_root = Node3D.new()
		_ghost_root.name = "MPGhosts"
		_level.add_child(_ghost_root)

	var w := clampf(delta * GHOST_LERP, 0.0, 1.0)
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		if not p.has("pos"):
			continue
		if not _ghosts.has(id) or not is_instance_valid(_ghosts[id]["body"]):
			_free_ghost(id)   # tidy up a half-dead entry before rebuilding it
			_ghosts[id] = _make_ghost(id)
		var g: Dictionary = _ghosts[id]
		var body: Node3D = g["body"]

		body.global_position = body.global_position.lerp(p["pos"], w)

		var vis: Node3D = body.get_node_or_null("Visuals")
		if vis != null:
			var t: Vector3 = p["rot"]
			vis.rotation = Vector3(
				lerp_angle(vis.rotation.x, t.x, w),
				lerp_angle(vis.rotation.y, t.y, w),
				lerp_angle(vis.rotation.z, t.z, w))

		var ap: AnimationPlayer = body.get_node_or_null("Visuals/AnimationPlayer")
		if ap != null:
			var want: String = ANIM_NAMES[clampi(int(p.get("anim", 0)), 0, ANIM_NAMES.size() - 1)]
			if ap.current_animation != want:
				ap.play(want)

		_update_ghost_pet(id, g, body, bool(p.get("pet", false)), delta)


func _update_ghost_pet(id: int, g: Dictionary, body: Node3D, pet_on: bool, delta: float) -> void:
	var sean = g.get("sean")
	if sean != null and not is_instance_valid(sean):
		sean = null
	if pet_on and sean == null:
		sean = load(SEAN_SCENE_PATH).instantiate()
		sean.set_script(null)   # sean.gd chases the LOCAL player; a copy must not
		sean.name = "MPSean_%d" % id
		_ghost_root.add_child(sean)
		sean.global_position = body.global_position
		g["sean"] = sean
	elif not pet_on and sean != null:
		sean.queue_free()
		g["sean"] = null
		return
	if sean != null:
		# same lazy follow as sean.gd
		sean.global_position = sean.global_position.lerp(body.global_position, clampf(delta, 0.0, 1.0))
		# only turn on the horizontal offset: looking straight up at a gull
		# hovering overhead makes look_at() colinear with UP and it complains
		var to: Vector3 = body.global_position - sean.global_position
		if Vector2(to.x, to.z).length() > 0.05:
			sean.look_at(body.global_position)


func _make_ghost(id: int) -> Dictionary:
	var body: Node3D = load(PLAYER_SCENE_PATH).instantiate()
	body.set_script(null)             # no player.gd: no camera grab, no input, no physics
	body.remove_from_group("player")  # must never be found by get_first_node_in_group("player")
	body.name = "MPGhost_%d" % id

	# strip the bits a remote copy must not carry (their own camera, and the
	# fog slabs that follow the local player around)
	for n in ["CamPivot", "FogVolume", "FogVolume2", "FogVolume3", "FogVolume4", "FogVolume5"]:
		var c := body.get_node_or_null(n)
		if c != null:
			body.remove_child(c)
			c.queue_free()

	# the Squawk animation drives "Squawk:playing", but that node is a flat
	# AudioStreamPlayer - swap in a 3D one so friends squawk from where they are
	var sq := body.get_node_or_null("Squawk")
	if sq != null:
		var stream = sq.stream
		body.remove_child(sq)
		sq.queue_free()
		var sq3 := AudioStreamPlayer3D.new()
		sq3.name = "Squawk"
		sq3.stream = stream
		sq3.unit_size = 20.0
		sq3.max_distance = 90.0
		body.add_child(sq3)

	body.collision_layer = 0          # purely decorative - never blocks anyone
	body.collision_mask = 0

	var label := Label3D.new()
	label.text = String(_peers[id].get("name", "Gull %d" % id))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = NAMETAG_SIZE
	label.outline_size = 16
	label.position = Vector3(0, 1.3, 0)
	body.add_child(label)

	_ghost_root.add_child(body)
	if _peers[id].has("pos"):
		body.global_position = _peers[id]["pos"]
	return {"body": body, "sean": null, "label": label}


func _free_ghost(id: int) -> void:
	if not _ghosts.has(id):
		return
	var g: Dictionary = _ghosts[id]
	if is_instance_valid(g["body"]):
		g["body"].queue_free()
	if g.get("sean") != null and is_instance_valid(g["sean"]):
		g["sean"].queue_free()


# ===========================================================================
#  BOATS
#  Whoever climbs aboard an idle boat becomes its driver and simulates it
#  locally, so steering feels instant for them. Everyone else freezes
#  boat.gd on their copy and follows the transform over the wire, gluing
#  themselves on locally -- so any number of gulls can pile onto one boat.
# ===========================================================================

func _driver_of(bname: String) -> int:
	var o: int = _boat_owner.get(bname, 0)
	return o if o != 0 else _world_authority   # nobody driving -> world sim peer


func _follow_remote_boat(b, bname: String, delta: float) -> void:
	var d = _boat_net.get(bname)
	if d != null:
		b.global_transform = b.global_transform.interpolate_with(d["x"], clampf(delta * BOAT_LERP, 0.0, 1.0))
		b.motor = d["m"]
	b.velocity = Vector3.ZERO

	var player = _local_player
	if player == null or not is_instance_valid(player):
		return

	var area: Area3D = b.get_node_or_null("Area3D")
	var lbl: Label3D = b.get_node_or_null("Label3D")
	var touching: bool = area != null and area.has_overlapping_bodies()

	if lbl != null:
		lbl.transparency = lerpf(lbl.transparency, 1.0 if touching else 0.0, delta * 10.0)

	if touching and not _ui_open and Input.is_action_just_pressed("select"):
		b.in_boat = not b.in_boat
		if b.in_boat:
			b.player_offset = b.to_local(player.position)

	if b.in_boat:
		if not b.was_in_boat:
			player.cam_distance = b.boat_cam_distance
		player.handle_input = false
		player.position = b.to_global(b.player_offset)
		if not touching:
			b.in_boat = false
	elif b.was_in_boat:
		player.cam_distance = player.base_cam_distance
		player.handle_input = true
	b.was_in_boat = b.in_boat


func _check_boarding(b, bname: String) -> void:
	var aboard: bool = b.in_boat
	if aboard == _aboard.get(bname, false):
		return
	_aboard[bname] = aboard
	var me := multiplayer.get_unique_id()
	if aboard:
		if multiplayer.is_server():
			_grant_boat(me, bname)
		else:
			_req_boat.rpc_id(1, bname)
	else:
		if multiplayer.is_server():
			_drop_boat(me, bname)
		else:
			_drop_boat_req.rpc_id(1, bname)


@rpc("any_peer", "call_remote", "reliable")
func _req_boat(bname: String) -> void:
	if multiplayer.is_server():
		_grant_boat(multiplayer.get_remote_sender_id(), bname)


@rpc("any_peer", "call_remote", "reliable")
func _drop_boat_req(bname: String) -> void:
	if multiplayer.is_server():
		_drop_boat(multiplayer.get_remote_sender_id(), bname)


func _grant_boat(id: int, bname: String) -> void:
	if _boat_owner.get(bname, 0) != 0:
		return          # already has a driver, so this gull is a passenger
	_set_boat_owner(bname, id)
	_rx_owner.rpc(bname, id)


func _drop_boat(id: int, bname: String) -> void:
	if _boat_owner.get(bname, 0) != id:
		return
	_set_boat_owner(bname, 0)
	_rx_owner.rpc(bname, 0)


@rpc("authority", "call_remote", "reliable")
func _rx_owner(bname: String, id: int) -> void:
	_set_boat_owner(bname, id)


@rpc("authority", "call_remote", "reliable")
func _rx_owner_table(table: Dictionary) -> void:
	for bname in table.keys():
		_set_boat_owner(String(bname), int(table[bname]))


func _set_boat_owner(bname: String, id: int) -> void:
	_boat_owner[bname] = id
	# seed the follow target so a boat we just lost does not snap to the origin
	var b = _boats.get(bname)
	if is_instance_valid(b) and _driver_of(bname) != multiplayer.get_unique_id():
		if not _boat_net.has(bname):
			_boat_net[bname] = {"x": b.global_transform, "m": int(b.motor)}


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rx_boat(bname: String, xform: Transform3D, motor: int) -> void:
	if _driver_of(bname) != multiplayer.get_remote_sender_id():
		return
	_boat_net[bname] = {"x": xform, "m": motor}


# ===========================================================================
#  OCEAN  (so boats sit at the same wave height on every screen)
# ===========================================================================

func _sync_ocean(delta: float) -> void:
	if multiplayer.get_unique_id() != _world_authority:
		return
	_ocean_accum += delta
	if _ocean_accum < 0.5:
		return
	_ocean_accum = 0.0
	var oc := get_tree().get_first_node_in_group("ocean")
	if oc != null and ("time" in oc):
		_rx_ocean.rpc(oc.time)


@rpc("any_peer", "call_remote", "reliable")
func _rx_ocean(t: float) -> void:
	# the wave clock comes from the world sim peer, which may be a client
	if multiplayer.get_remote_sender_id() != _world_authority:
		return
	var oc := get_tree().get_first_node_in_group("ocean")
	if oc != null and ("time" in oc) and absf(oc.time - t) > 0.15:
		oc.time = t


# ===========================================================================
#  ODDS AND ENDS
# ===========================================================================

func connected_count() -> int:
	return _peers.size()


func remote_names() -> Array:
	var out := []
	for id in _peers.keys():
		out.append(String(_peers[id].get("name", "Gull %d" % id)))
	return out


func peer_names() -> Array:
	var out := ["%s  (you)" % player_name]
	out.append_array(remote_names())
	return out


func set_player_name(n: String) -> void:
	n = n.strip_edges()
	if n == "":
		return
	player_name = n
	_save_name(n)
	if online:
		_rx_hello.rpc(player_name)


func _refresh_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.refresh()


func _load_name() -> String:
	if FileAccess.file_exists(NAME_FILE):
		var f := FileAccess.open(NAME_FILE, FileAccess.READ)
		if f != null:
			var n := f.get_as_text().strip_edges()
			if n != "":
				return n
	var u := OS.get_environment("USERNAME")
	if u == "":
		u = OS.get_environment("USER")
	return u if u != "" else "Gull"


func _save_name(n: String) -> void:
	var f := FileAccess.open(NAME_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(n)


func _parse_cmdline() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--mp-name="):
			set_player_name(a.substr(10))
	# --mp-server swaps straight to the bare server scene, so the same exported
	# binary works as both the game and the dedicated server
	if "--mp-server" in args:
		get_tree().change_scene_to_file(SERVER_SCENE_PATH)
		return
	for a in args:
		if a == "--mp-host":
			host_game()
		elif a.begins_with("--mp-join="):
			join_game(a.substr(10))
