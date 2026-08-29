# mp_test — throwaway playtest multiplayer

Temporary. **Not for the game jam build.**

Lets you and your friends run around the same island so you can playtest.
It is deliberately dumb: no lag compensation, no cheat protection, no saving,
no syncing of quests/chips/poop. Just enough to mess about together.

## What it syncs

| Thing | How |
| --- | --- |
| Other players' seagulls | position, facing and animation at 20 Hz, with a name tag over their head |
| Squawks | the remote copy gets a 3D audio player, so you hear friends squawk from where they are |
| Pet Sean | whether each player has their pet out (`P`). Everyone still unlocks their own |
| Boats | first gull aboard drives; everyone else can pile on. Unlimited passengers |
| Ocean | wave time, so boats sit at the same height on every screen |

Not synced: quests, chip counts, poop, humans/NPCs, the mafia lord. Everyone
runs their own copy of those.

## Playing

Press **F3** in game. That pauses and opens the connect panel.

* One person clicks **Host**. The panel lists their IP addresses.
* Everyone else puts that address in **Host address** and clicks **Join**.
* **F3** again to close and play.

The address field takes an **IP or a hostname** — `192.168.1.50`,
`play.example.com`, or either with an explicit `:27015` on the end. Hostnames
are resolved before connecting, so a name that does not exist fails
immediately with a clear message instead of hanging.

Command line works too:

```
"Seagull Game Jam.exe" --mp-host
"Seagull Game Jam.exe" --mp-join=play.example.com
"Seagull Game Jam.exe" --mp-name=Jasey
```

### Getting friends connected

* **Same house / same wifi** — use the local `192.168.x.x` address shown in
  the panel. Nothing else needed.
* **Over the internet** — forward UDP port **27015** to whichever machine is
  hosting. If that is a pain, install a free virtual LAN on every machine
  (ZeroTier, Radmin VPN, Hamachi) and use the address it hands out.

---

# Running it on your own server

There is a dedicated server scene, `mp_test/server.tscn`. It loads **no
island at all** — it is just a relay and a referee that decides who is driving
which boat. That keeps it tiny: no meshes, no physics, no rendering.

Because the server has no world of its own, one of the *connected players* is
picked to simulate the things nobody owns — boats sitting empty, and the ocean
wave clock. If that player leaves, the job is handed to someone else
automatically. Everyone else's boats follow over the wire exactly as before.

## Exporting for Linux

You already have a **Linux** export preset. Two ways to do this:

**Option A — nothing to configure (recommended).** Export the Linux preset as
normal and run the binary with `--mp-server`:

```
./SeagullGameJam.x86_64 --headless --mp-server
./SeagullGameJam.x86_64 --headless --mp-server --mp-port=27015
```

The same binary is still a normal game if you run it without the flag, so one
export covers both.

**Option B — a build that is only ever a server.** In the export dialog, on
the Linux preset, open the **Features** tab and put `dedicated_server` in
**Custom (comma-separated)**. `project.godot` already has the matching
override:

```
run/main_scene.dedicated_server="res://mp_test/server.tscn"
```

so that build boots straight into the server scene and never loads the island.
Then you only need:

```
./SeagullGameJam.x86_64 --headless
```

`--headless` is required either way if the box has no display.

## Keeping it running

Quick and dirty:

```
tmux new -s gulls
./SeagullGameJam.x86_64 --headless --mp-server
```

(`Ctrl-B` then `D` to detach, `tmux attach -t gulls` to get back.)

As a systemd service, `/etc/systemd/system/seagull.service`:

```ini
[Unit]
Description=Seagull playtest server
After=network.target

[Service]
Type=simple
User=YOUR_USER
WorkingDirectory=/opt/seagull
ExecStart=/opt/seagull/SeagullGameJam.x86_64 --headless --mp-server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```
sudo systemctl enable --now seagull
journalctl -u seagull -f      # watch gulls joining and leaving
```

Open UDP **27015** on the box's firewall and point your DNS record at it, then
everyone joins with `play.example.com`.

## Server console output

```
[MP] Dedicated server listening on port 27015
[MP] waiting for gulls...
[MP] idle boats + waves now simulated by peer 1900135484
[MP] AlphaGull joined
[MP] BetaGull joined
[MP] AlphaGull left
```

Run it with a display instead of `--headless` and you get the same thing as a
status screen.

---

## Turning it off

Set `ENABLED := false` at the top of `mp_test.gd`. The game then behaves
exactly as it did before — F3 does nothing, nothing is spawned, no boat is
touched.

## Deleting it properly

1. Delete this whole `mp_test/` folder.
2. Delete these two lines from `project.godot`:

   ```
   [autoload]
   MPTest="*res://mp_test/mp_test.gd"

   [application]
   run/main_scene.dedicated_server="res://mp_test/server.tscn"
   ```

3. If you used Option B above, clear `dedicated_server` out of the Linux
   preset's custom features.

That is everything. **No existing game script or scene was modified to add
this** — it drives the normal `player.tscn` / `boat.gd` / `sean.tscn` from the
outside, so there are no hooks left behind anywhere.

## How it works, roughly

* Your own seagull is never networked *into* — you play it exactly as in single
  player, and the autoload just reads its position/animation and broadcasts it.
* Other players appear as copies of `player.tscn` with the script stripped off
  (so they have no camera, no input, no physics) and collision disabled, so
  they can never block or trip you up.
* Boats: whoever boards an idle boat claims it and simulates it locally with
  the untouched `boat.gd`, so steering feels instant for the driver. Everyone
  else calls `set_physics_process(false)` on their copy and lerps it toward the
  driver's transform, then glues themselves to it locally — which is why any
  number of gulls can ride one boat.
* Boats nobody is in, plus the wave clock, belong to whoever `_world_authority`
  points at: the host on a listen server, or a nominated player when running
  against a dedicated server.
