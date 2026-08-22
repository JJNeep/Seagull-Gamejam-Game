extends PanelContainer

# ============================================================================
#  HOW A SPECTRUM ANALYSER WORKS  (annotated - read top to bottom)
# ============================================================================
#  The big idea: sound arriving at your speakers is ONE wobbly line (amplitude
#  over time). A "Fourier transform" re-describes that same wobble as a stack
#  of pure sine waves at different frequencies, and tells you how loud each one
#  is. Godot's AudioEffectSpectrumAnalyzer does that maths for you, every
#  frame, and hands you a lookup table: "how much energy is between X Hz and
#  Y Hz?"
#
#  Everything below is just: ask that question 32 times, convert the answer
#  into a number a human can look at, and draw a rectangle.
# ============================================================================


# --- TUNING KNOBS ----------------------------------------------------------

const BAR_COUNT : int = 32
# How many slices we chop the frequency range into. Purely a display choice -
# the analyser itself doesn't have "bars", we invent them by asking for 32
# different frequency windows.

const FREQ_MAX : float = 11050.0
# The highest frequency we bother looking at, in Hz.
# Why this oddly specific number? CD-quality audio is sampled 44100 times a
# second. The Nyquist limit says you can only ever detect frequencies up to
# HALF your sample rate, so 22050 Hz is the theoretical ceiling. 11050 is
# roughly half of THAT again - chosen because almost nothing musically
# interesting lives above ~11 kHz (it's mostly cymbal shimmer and air), so
# including it would waste half your bars on near-silent slivers.

const MIN_DB: int = 60
# Our "noise floor", in decibels below maximum. Anything quieter than -60 dB
# we treat as pure silence. Used below to squash the decibel scale into 0..1.


# --- STATE -----------------------------------------------------------------

var spectrum : AudioEffectSpectrumAnalyzerInstance
# NOTE the word "Instance". There are two related things in Godot:
#   AudioEffectSpectrumAnalyzer         = the resource / settings you configure
#                                         in the Audio panel of the editor.
#   AudioEffectSpectrumAnalyzerInstance = the LIVE, running copy of it that is
#                                         actually chewing on audio right now.
# You can only query the live instance. Fetching it is done in _ready().

var heights: Array[Height] = []
# One Height object per bar (see the little class at the bottom of the file).
# This is the smoothing memory: raw spectrum data is extremely twitchy and
# would look like static, so we remember each bar's previous value and ease
# towards the new one instead of snapping.

var bar_width: float = 0.0
# Pixels per bar. Recalculated whenever the panel is resized.


func _ready() -> void:
	spectrum = AudioServer.get_bus_effect_instance(1, 0)
	# ^^^ THE MOST IMPORTANT LINE IN THE FILE, and the one the tutorial
	# definitely didn't explain.
	#   first arg  (1) = which audio BUS. Bus 0 is always Master. Bus 1 is the
	#                    second bus in your Audio panel - in this project that
	#                    is the "Music" bus.
	#   second arg (0) = which EFFECT slot on that bus. The spectrum analyser
	#                    is the first (and only) effect on Music, so slot 0.
	#
	# These are raw magic numbers, which is fragile: add a bus above Music, or
	# drag another effect above the analyser, and this silently grabs the wrong
	# thing (or null-crashes). The robust version is:
	#     var bus := AudioServer.get_bus_index("Music")
	#     spectrum = AudioServer.get_bus_effect_instance(bus, 0)
	# Worth changing when you write your own.
	#
	# CRUCIAL CONSEQUENCE: this only ever sees audio routed through the Music
	# bus. Your Speakers/Music player in level_01.tscn already has
	# `bus = &"Music"`, which is why this works at all.

	_on_resized()

	for i: int in BAR_COUNT:
		heights.append(Height.new())
		# Pre-create the smoothing memory so _update_spectrum_data can just
		# index into it without checking whether it exists.


func _process(_delta: float) -> void:
	_update_spectrum_data()   # read the audio, update our numbers
	queue_redraw()            # tell Godot "my visuals are stale, call _draw()"
	# Note: _draw() is NOT called every frame automatically. queue_redraw()
	# schedules exactly one call for the end of this frame. Since we call it
	# every frame, we effectively redraw every frame.


func _draw() -> void:
	# _draw() is Godot's immediate-mode canvas. Whatever you draw here exists
	# for one frame only, in the node's LOCAL coordinates, and is wiped before
	# the next _draw(). There are no child nodes, no scene tree - just paint.
	for i: int in BAR_COUNT:
		var l_color: Color = Color.from_hsv((BAR_COUNT * 0.6 + i * 0.5) / BAR_COUNT, 0.5, 0.6)
		# from_hsv(hue, saturation, value), all 0..1.
		# Hue is a position on the colour wheel: 0=red, 0.33=green, 0.66=blue,
		# 1=back to red. This expression just walks the wheel as `i` increases,
		# giving each bar a slightly different colour. The `BAR_COUNT * 0.6`
		# part is a fixed starting offset - it only shifts where on the wheel
		# the gradient begins. It's cosmetic; you can replace this whole line
		# with anything.

		var l_rect: Rect2 = Rect2(
			i * bar_width,              # x: left edge of this bar
			size.y - heights[i].acutal, # y: TOP of the bar. In Godot 2D, y=0 is
										#    the TOP of the screen and y grows
										#    downward - so to make a bar grow
										#    upward from the floor you subtract
										#    its height from the bottom edge.
			bar_width - 2,              # width, minus 2px to leave a gap
			heights[i].acutal           # height (the audio-driven value)
		)

		draw_rect(l_rect, l_color)


func _update_spectrum_data() -> void:
	# This is the actual analysis. Everything above is presentation.

	var l_prev_hz: float = 0.0
	# We walk up the frequency range in a sliding window. prev_hz is the bottom
	# of the current window, l_hz is the top; after each bar the top becomes
	# the new bottom. Bar 0 covers 0-345 Hz, bar 1 covers 345-690 Hz, and so on.

	for i: int in BAR_COUNT:
		var l_hz: float = (i + 1) * FREQ_MAX / BAR_COUNT
		# LINEAR division: every bar is the same 345 Hz wide.
		#
		# !! THIS IS THE BIGGEST WEAKNESS IN THE TUTORIAL CODE. Human hearing
		# is LOGARITHMIC - we perceive 100->200 Hz as the same musical distance
		# as 5000->10000 Hz (both are one octave). With linear bars, bar 0 alone
		# swallows the kick drum, the bass, and most of the vocal range, while
		# bars 20-31 split a single octave of near-silent hiss between them.
		# That's why these things often look like "one giant bar and 31 dead
		# ones". A log split (each bar covering a fixed musical RATIO rather
		# than a fixed Hz count) looks dramatically better. Worth trying.

		var l_magnitiude: float = spectrum.get_magnitude_for_frequency_range(l_prev_hz, l_hz).length()
		# THE ONE API CALL THAT MATTERS. Returns a Vector2, NOT a float:
		#   .x = magnitude in the LEFT channel
		#   .y = magnitude in the RIGHT channel
		# .length() is Pythagoras on those two - it collapses stereo into a
		# single mono loudness. (You could use .x and .y separately if you
		# wanted a left light and a right light...)
		#
		# The result is LINEAR amplitude: roughly 0.0 = silence, 1.0 = full
		# scale. It is NOT a percentage and it is NOT perceptual.

		var l_energy: float = clampf((MIN_DB + linear_to_db(l_magnitiude)) / MIN_DB, 0, 1)
		# Converting that raw amplitude into something usable. Read it
		# inside-out:
		#
		#   linear_to_db(m)     Amplitude is a terrible scale to eyeball,
		#                       because loudness is logarithmic. Halving the
		#                       amplitude doesn't look or sound "half as loud".
		#                       dB fixes that. Result: 1.0 -> 0 dB,
		#                       0.5 -> -6 dB, 0.1 -> -20 dB, 0.001 -> -60 dB,
		#                       and true silence -> -infinity.
		#
		#   MIN_DB + db         Shifts the range up so our -60 dB floor becomes
		#                       zero.  -60 dB -> 0,  0 dB -> 60.
		#
		#   / MIN_DB            Divides by 60 to normalise into 0..1.
		#
		#   clampf(..., 0, 1)   Anything below the floor went negative (and
		#                       silence went to -infinity); anything above 0 dB
		#                       went over 1. Clamp both ends.
		#
		# NET RESULT: l_energy is a clean 0.0 (silent) .. 1.0 (loud) value.
		# *** For your disco lights, THIS is the number you actually want. ***
		# Everything after this point is display-specific fluff.

		var l_height: float = l_energy * size.y * 10.0
		# Scale 0..1 up to pixels. The `* 10.0` is a pure fudge factor, and
		# it's only there to cancel out a bug further down - see the note at
		# the end of this loop.

		# --- SMOOTHING / ENVELOPE ------------------------------------------
		# Raw spectrum values flicker violently frame to frame. The trick used
		# everywhere in audio visualisation is FAST ATTACK, SLOW DECAY: jump up
		# instantly when the music gets louder, fall back down gradually. That
		# is what makes bars feel punchy rather than jittery.

		if l_height > heights[i].high:
			heights[i].high = l_height
			# Louder than last frame -> snap straight up. Fast attack.
		else:
			heights[i].high = lerp(heights[i].high, l_height, 0.1)
			# Quieter -> ease down 10% of the remaining gap per frame.
			# Slow decay.
			#
			# lerp(from, to, weight) = from + (to - from) * weight.
			# Called repeatedly with a small weight, it's an exponential glide.
			# !! Framerate-dependent: at 120fps this decays twice as fast as at
			# 60fps. The framerate-independent fix is
			#     var w = 1.0 - pow(0.9, delta * 60.0)
			# Ignore for a jam, but know it's there.

		if l_height <= 0.0:
			heights[i].low = lerp(heights[i].low, l_height, 0.1)
			# !! This branch is effectively DEAD CODE. l_height is
			# energy * size.y * 10, and energy is clamped to >= 0, so l_height
			# is only ever <= 0 when it is exactly 0. `low` therefore sits at
			# 0.0 basically forever.

		heights[i].acutal = lerp(heights[i].low, heights[i].high, 0.1)
		# !! And here is the bug that the `* 10.0` is papering over. This is
		# NOT a smoothing step - it doesn't blend with the PREVIOUS `acutal`,
		# it recomputes from scratch every frame. With `low` stuck at 0, this
		# line reduces to:
		#         acutal = high * 0.1
		# i.e. it just divides the height by ten. Which is exactly why the
		# author multiplied by ten earlier. The two cancel out, and the whole
		# `low` mechanism does nothing at all.
		#
		# So: the tutorial's "smoothing" is really just the high/attack-decay
		# logic. When you write your own, drop `low`, drop the `* 10.0`, and
		# keep the fast-attack/slow-decay pattern - that part is genuinely good.

		l_prev_hz = l_hz  # this bar's ceiling becomes the next bar's floor


func _on_resized() -> void:
	# Connected to the `resized` signal in "spectrum test.tscn". Recomputes how
	# wide each bar should be whenever the container changes size.
	bar_width = size.x / BAR_COUNT
	print(bar_width)  # leftover debug print - safe to delete


class Height:
	# A tiny bundle of three floats per bar. (Note "acutal" is a typo for
	# "actual" that is consistent throughout the file - so it works, but
	# rename it in your own version.)
	var high: float    # the fast-attack/slow-decay envelope - the useful one
	var low: float     # vestigial, always 0 (see notes above)
	var acutal : float # what actually gets drawn
