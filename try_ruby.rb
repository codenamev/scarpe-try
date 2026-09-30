# Try Ruby! -- a little room where Ruby talks back. Two foxes live here too.
#
# Type Ruby into the console and it answers. Twenty-one lessons walk you from `2 + 6` to
# drawing and animating on a Shoes canvas, and at the end there is a secret word.
#
# For _why, who made Try Ruby, Shoes, Hackety Hack and the foxes, and taught a lot of us that
# a programming language can be a playground. Wherever you are: chunky bacon.
#
#   run it:  cd ~/scarpe && bundle exec ruby exe/scarpe --native ~/scarpe-try/try_ruby.rb
#
# Keys, in the console: Return runs a line, Escape drops the line (or the unfinished method),
# Ctrl-P and Ctrl-N walk back and forth through what you typed, Ctrl-L clears the console.
# Words the console knows by itself: help, next, back, lessons, play, clear, reset, mute.

require "json"
require "fileutils"
require "tmpdir"
require "timeout"

# Fonts that travel with the app: Chewy (Apache 2.0) for headings, Patrick Hand (OFL) for the
# prose. Fall back to something rounded if the files ever go missing.
FONT_DIR = File.join(__dir__, "fonts")
def carried_font(file, fallback)
  path = File.join(FONT_DIR, file)
  (File.exist?(path) && font(path)&.first) || fallback
rescue StandardError
  fallback
end
CHEWY = carried_font("Chewy-Regular.ttf", "Arial Rounded MT Bold, Helvetica, sans-serif")
HAND = carried_font("PatrickHand-Regular.ttf", "Chalkboard SE, Comic Sans MS, sans-serif")
MONO = "monospace" # Menlo on a Mac; the renderer picks the best mono it can find

# The palette: old paper, fox orange, ruby red and a plum-dark console.
PAPER = "#fbf3df"
PAPER_DEEP = "#f1dfb8"
INK = "#3d2b1f"
INK_SOFT = "#7a6250"
RUBY = "#cc342d"
RUBY_DEEP = "#8f1f1a"
FOX = "#e8702a"
FOX_RED = "#d9542b"
FOX_GOLD = "#ef8a3c"
CARD = "#fffaf0"
PLUM = "#2b2233"
PLUM_LIGHT = "#3b3046"
PROMPT = "#ffcf5c"
RESULT = "#9be08a"
OOPS = "#ff8f86"
SAID = "#b9c8ff"
CHALK = "#f4ead8"
BACON = "#c8453b"
BACON_FAT = "#f7cdb4"

# Where the foxes remember how far you got.
module Keepsake
  DIR = if RUBY_PLATFORM.include?("darwin")
    File.join(Dir.home, "Library", "Application Support", "Try Ruby")
  else
    File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")), "try_ruby")
  end
  FILE = File.join(DIR, "keepsake.json")

  def self.load
    JSON.parse(File.read(FILE))
  rescue Errno::ENOENT, JSON::ParserError
    {}
  end

  def self.save(state)
    FileUtils.mkdir_p(DIR)
    File.write("#{FILE}.tmp", JSON.pretty_generate(state))
    File.rename("#{FILE}.tmp", FILE) # a crash mid-write never leaves half a file
  rescue SystemCallError
    # a read-only home: the foxes will simply forget
  end
end

# Little chimes, written once as WAV files and played with afplay (macOS). Silent elsewhere.
module Chime
  RATE = 22_050
  DIR = Dir.mktmpdir("try-ruby-chimes")
  at_exit { FileUtils.rm_rf(DIR) }

  class << self
    attr_accessor :muted

    def play(*notes, seconds: 0.14, volume: 0.18)
      return if muted

      path = File.join(DIR, "#{notes.join("-")}-#{seconds}.wav")
      write(path, notes, seconds, volume) unless File.exist?(path)
      Process.detach(spawn("afplay", path, out: File::NULL, err: File::NULL))
    rescue SystemCallError
      # no afplay here (Linux, Windows): stay silent
    end

    def yay = play(523, 659, 784, 1047)
    def boop = play(330, 262, seconds: 0.12, volume: 0.12)
    def fanfare = play(523, 659, 784, 1047, 784, 1047, 1319, seconds: 0.16)

    private

    # A 16-bit mono WAV of the notes one after another, each faded in and out so nothing clicks.
    def write(path, notes, seconds, volume)
      samples = notes.flat_map do |hz|
        Array.new((RATE * seconds).round) do |i|
          t = i.fdiv(RATE)
          fade = [t / 0.005, (seconds - t) / 0.04, 1].min
          (Math.sin(2 * Math::PI * hz * t) * volume * fade * 32_767).round
        end
      end
      data = samples.pack("s<*")
      header = ["RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16, "data", data.bytesize]
      File.binwrite(path, header.pack("a4Va4a4VvvVVvva4V") + data)
    end
  end
end

# What one line of Ruby did.
Answer = Struct.new(:code, :value, :error, :output, :sandbox, keyword_init: true) do
  def ok? = error.nil?
  def local(name) = sandbox.__local(name)
end

# The console's own little world. Code typed at the prompt runs in here, with its own local
# variables and its own methods, and anything Shoes it asks for (oval, star, fill, animate...)
# is drawn on the canvas, never on the app around it.
class Sandbox
  class NoLeaving < StandardError; end

  # Things the console must not do to the app it lives in.
  OFF_LIMITS = %i[close exit quit visit window dialog url exit_all].freeze

  def initialize(app, canvas)
    @__app = app
    @__canvas = canvas
    @__said = +""
    @__timers = []
    @__binding = __fresh_binding
  end

  def __run(code, line)
    @__binding.eval(code, "(console)", line)
  end

  def __local(name)
    @__binding.local_variable_defined?(name) ? @__binding.local_variable_get(name) : nil
  end

  def __take_said
    said = @__said
    @__said = +""
    said
  end

  def __stop_timers
    @__timers.each do |t|
      t.stop
      t.remove # a stopped timer is still a child of the canvas until it goes
    rescue StandardError
      nil
    end
    @__timers.clear
  end

  def puts(*things)
    things = [""] if things.empty?
    things.flatten.each do |thing|
      text = thing.to_s
      @__said << text
      @__said << "\n" unless text.end_with?("\n")
    end
    nil
  end

  def print(*things)
    things.each { |thing| @__said << thing.to_s }
    nil
  end

  def p(*things)
    things.each { |thing| @__said << thing.inspect << "\n" }
    things.size <= 1 ? things.first : things
  end
  alias_method :pp, :p

  def gets = nil
  def exit(*) = raise(NoLeaving, "the foxes are sitting on the door. You can't leave from in here.")
  alias_method :exit!, :exit
  alias_method :abort, :exit
  def inspect = "main"
  def to_s = "main"

  # `clear` in the console clears the canvas, not the whole window.
  def clear(&block)
    __stop_timers
    @__canvas.clear(&block)
    nil
  end

  # Timers the console starts draw on the canvas too, and stop when it is reset. One that
  # raises stops itself and says why in the console, instead of raising every frame.
  %i[animate every timer].each do |name|
    define_method(name) do |*args, &block|
      handle = nil
      handle = @__app.send(name, *args) do |*frame|
        @__app.__on_canvas { block.call(*frame) }
      rescue StandardError, ScriptError => e
        handle&.stop
        @__app.__timer_trouble(e)
      end
      @__timers << handle
      handle
    end
  end

  def method_missing(name, *args, **opts, &block)
    return super if OFF_LIMITS.include?(name) || !@__app.respond_to?(name)

    @__app.send(name, *args, **opts, &block)
  end

  def respond_to_missing?(name, include_private = false)
    (!OFF_LIMITS.include?(name) && @__app.respond_to?(name)) || super
  end

  private

  # Inside instance_eval, `def` makes methods on this one sandbox, so reset forgets them.
  def __fresh_binding = instance_eval { binding }
end

# One step of the path. `text` may hold `code` in backticks; `try` is what the chip pastes,
# and `%{name}` in either becomes the name you typed in lesson two.
Lesson = Struct.new(:title, :text, :try, :check, :cheer, keyword_init: true)

LESSONS = [
  Lesson.new(
    title: "Hello, Ruby",
    text: "This is a console. You type, Ruby answers. Let's start small and add two numbers. Type `2 + 6` and press Return.",
    try: "2 + 6",
    check: ->(a) { a.ok? && a.value == 8 },
    cheer: "Eight! A fine round number. It wears a belt."
  ),
  Lesson.new(
    title: "Words wear quotes",
    text: "Words need quotes, or Ruby thinks they are orders. A word in quotes is a string. Type your own name, in quotes.",
    try: "\"Jimmy\"",
    check: ->(a) { a.ok? && a.value.is_a?(String) && a.code.strip.match?(/\A["']/) },
    cheer: "Hello, %{name}! The foxes have written you on a leaf."
  ),
  Lesson.new(
    title: "Backwards",
    text: "Strings know tricks. Put a dot after one, then the trick's name. Here is `reverse`:",
    try: "%{quoted}.reverse",
    check: ->(a) { a.ok? && a.value.is_a?(String) && a.code.include?(".reverse") },
    cheer: "That's you, seen from the other side of a mirror."
  ),
  Lesson.new(
    title: "How long?",
    text: "`length` counts the letters. Spaces count too; they are very thin letters.",
    try: "%{quoted}.length",
    check: ->(a) { a.ok? && a.value.is_a?(Integer) && a.code.match?(/\.(length|size)/) },
    cheer: "Counted! Ruby never loses count. It has lots of fingers."
  ),
  Lesson.new(
    title: "Seconds, please",
    text: "You can multiply a string. Ruby doesn't even blink.",
    try: "%{quoted} * 5",
    check: ->(a) { a.ok? && a.value.is_a?(String) && a.code.include?("*") },
    cheer: "Now there are five of you. The foxes are a little nervous."
  ),
  Lesson.new(
    title: "An honest mistake",
    text: "What happens if we reverse a number? Try it and watch the red.",
    try: "40.reverse",
    check: ->(a) { a.error.is_a?(NoMethodError) },
    cheer: "See? Numbers don't know `reverse`. Red isn't bad news, it's just news."
  ),
  Lesson.new(
    title: "A change of clothes",
    text: "`to_s` turns a thing into a string, and a string can reverse! (`to_i` goes the other way, and `to_a` makes arrays.)",
    try: "40.to_s.reverse",
    check: ->(a) { a.ok? && a.value == "04" },
    cheer: "Oh-four! A number in a string's clothes."
  ),
  Lesson.new(
    title: "Lists",
    text: "Square brackets make an array: a list of things, in a row, holding hands.",
    try: "[12, 47, 35]",
    check: ->(a) { a.ok? && a.value.is_a?(Array) },
    cheer: "A list! The foxes keep one of their favourite snacks."
  ),
  Lesson.new(
    title: "The biggest",
    text: "Arrays know tricks too. Ask one for its `max`:",
    try: "[12, 47, 35].max",
    check: ->(a) { a.ok? && a.code.match?(/\.(max|min)/) },
    cheer: "Forty-seven wins. It was very modest about it."
  ),
  Lesson.new(
    title: "Keep it",
    text: "Give your list a name, so you can use it again. A name like this is a variable.",
    try: "ticket = [12, 47, 35]",
    check: ->(a) { a.ok? && a.local(:ticket).is_a?(Array) },
    cheer: "It's yours now. Type `ticket` any time and it'll be right there."
  ),
  Lesson.new(
    title: "Tidy up",
    text: "`sort!` sorts it. The `!` means: change the real thing, not a copy of it.",
    try: "ticket.sort!",
    check: ->(a) { a.ok? && a.code.include?("sort") && a.value.is_a?(Array) },
    cheer: "Tidy! Now type `ticket` and see: it stayed sorted."
  ),
  Lesson.new(
    title: "A pocket of pairs",
    text: "A hash keeps pairs: a key and its value. `:splendid` is a symbol, a word that never changes. Tiny and cheap, like a pebble.",
    try: "books = { \"Poignant Guide\" => :splendid }",
    check: ->(a) { a.ok? && a.local(:books).is_a?(Hash) && !a.local(:books).empty? },
    cheer: "A splendid little bookshelf."
  ),
  Lesson.new(
    title: "Look it up",
    text: "Get a value back out by its key, in square brackets:",
    try: "books[\"Poignant Guide\"]",
    check: ->(a) { a.ok? && a.code.include?("books[") && !a.value.nil? },
    cheer: "Found it, first try. Hashes have wonderful memories."
  ),
  Lesson.new(
    title: "Blocks",
    text: "Curly braces hold a block: a little bit of code to run later, or many times over.",
    try: "3.times { print \"Odelay! \" }",
    check: ->(a) { a.ok? && !a.output.empty? && a.code.match?(/times|each/) },
    cheer: "Odelay odelay odelay! A block is a small machine."
  ),
  Lesson.new(
    title: "A word of your own",
    text: "Teach Ruby a new word with `def`. (You can also spread it over three lines: `def shout(word)`, then the middle, then `end`. The console waits for the `end`.)",
    try: "def shout(word) = word.upcase + \"!\"",
    check: ->(a) { a.ok? && a.value.is_a?(Symbol) && a.code.match?(/\bdef\b/) },
    cheer: "Ruby knows `%{method}` now. It was a quick learner."
  ),
  Lesson.new(
    title: "Use it",
    text: "Now say it. Your method takes a word and gives it back, louder.",
    try: "shout \"chunky bacon\"",
    check: ->(a) { a.ok? && a.value.is_a?(String) && a.code.include?("shout") },
    cheer: "CHUNKY BACON!!"
  ),
  Lesson.new(
    title: "Shoes!",
    text: "This whole window is made of Shoes, a toolkit _why built so that drawing is as easy as talking. The canvas below does what you tell it.",
    try: "oval 40, 30, 90",
    check: ->(a) { a.ok? && a.value.is_a?(Shoes::Oval) },
    cheer: "A circle! Every great drawing starts with one."
  ),
  Lesson.new(
    title: "Paint",
    text: "Pick a colour first, then draw. Colours have names: `red`, `gold`, `teal`, `hotpink`...",
    try: "fill gold; star 200, 70, 5, 50, 22",
    check: ->(a) { a.ok? && a.value.is_a?(Shoes::Star) },
    cheer: "A star. The foxes want to wish on it."
  ),
  Lesson.new(
    title: "Lots of things",
    text: "Blocks and drawing together make patterns. `i` counts up, 0, 1, 2...",
    try: "12.times { |i| oval i * 27, 118, 24, fill: rgb(i * 20, 90, 200) }",
    check: ->(a) { a.ok? && a.code.match?(/times|each|upto/) && a.code.match?(/oval|rect|star|line|arrow/) },
    cheer: "A whole parade of dots, and you only wrote one line."
  ),
  Lesson.new(
    title: "Make it move",
    text: "`animate` runs its block many times a second. Name a shape with `@`, then move it each frame.",
    try: "@spot = oval 0, 60, 30, fill: hotpink; animate(30) { |i| @spot.move(i * 4 % 330, 60) }",
    check: ->(a) { a.ok? && a.code.match?(/animate|every/) },
    cheer: "It moves! It's alive! (You can type `clear` to make it stop.)"
  ),
  Lesson.new(
    title: "The secret word",
    text: "One last thing. Every Rubyist learns the secret word sooner or later. It is a symbol, and it goes like this:",
    try: ":chunky_bacon",
    check: ->(a) { a.ok? && a.value == :chunky_bacon },
    cheer: "CHUNKY BACON!!! You did every lesson. The console is yours now."
  )
].freeze

# Fun things for the playground card, once the lessons are done (or skipped).
PLAYTHINGS = [
  "rand(100)",
  "\"chunky bacon\".split.map(&:capitalize)",
  "(1..20).select(&:even?)",
  "%w[fox fox bacon fox].tally",
  "\"foxes\".chars.shuffle.join",
  "(1..10).map { |n| n * n }",
  "background \"#fdf0d5\"..\"#f4a261\"",
  "30.times { oval rand(330), rand(150), 20 }",
  "fill teal; nostroke; rect 20, 20, 300, 120, 30",
  "9.times { |i| star 20 + i * 38, 80, 5, 18, 8 }",
  "stroke red; strokewidth 3; 12.times { |i| line 0, 0, 350, i * 14 }",
  "@r = rect 10, 40, 50, 50; animate(30) { |i| @r.move(i * 3 % 300, 40) }",
  "para \"Hello from the console!\", size: 24",
  "clear"
].freeze

QUIPS = [
  "Ooh.", "The foxes approve.", "Neat!", "Ruby says so!", "Sharp!", "Tidy work.",
  "Try another!", "We like that one.", "Hm! Clever.", "Yes, yes, YES."
].freeze

PUZZLED = [
  "Oops! Red is just Ruby pointing at something.",
  "The foxes squint at that one. Read the red line, it helps.",
  "Nearly! Ruby is fussy about spelling.",
  "Hmm. Even foxes make that one."
].freeze

Shoes.app(title: "Try Ruby!", width: 1000, height: 680, resizable: false) do
  style(Shoes::Para, font: HAND, stroke: INK, size: 16)
  style(Shoes::Link, stroke: RUBY_DEEP)
  style(Shoes::LinkHover, stroke: RUBY)

  url "/", :front_door
  url "/try", :console_room

  # ---------------------------------------------------------------- the foxes

  # A sitting fox, drawn from ovals and curves in a placed slot, so the whole fox moves with
  # one `move`. `k` scales it (1.0 is 140 x 134); `mirror` turns it to face the other way.
  def fox(left, top, k: 1.0, coat: FOX, mirror: false)
    w = 140
    dark = "#4a2616"
    cream = "#fff4e2"
    flip = ->(x) { mirror ? w - x : x }
    blob = lambda do |x, y, ow, oh, colour|
      x = w - x - ow if mirror
      oval((x * k).round(1), (y * k).round(1), (ow * k).round(1), (oh * k).round(1), fill: colour, strokewidth: 0)
    end
    curve = lambda do |colour, start, *legs|
      shape(fill: colour, strokewidth: 0) do
        move_to(flip.(start[0]) * k, start[1] * k)
        legs.each do |leg|
          if leg.size == 2
            line_to(flip.(leg[0]) * k, leg[1] * k)
          else
            curve_to(flip.(leg[0]) * k, leg[1] * k, flip.(leg[2]) * k, leg[3] * k, flip.(leg[4]) * k, leg[5] * k)
          end
        end
      end
    end

    parts = { home: [left, top] }
    parts[:slot] = stack(left: left, top: top, width: (w * k).ceil, height: (134 * k).ceil) do
      curve.(coat, [72, 127], [112, 134, 136, 112, 132, 84], [130, 64, 120, 52, 110, 54],
        [118, 72, 112, 98, 76, 104]) # tail
      curve.(cream, [110, 54], [120, 50, 132, 62, 132, 80], [126, 76, 120, 74, 114, 72],
        [112, 66, 110, 60, 110, 54]) # its tip
      blob.(28, 62, 64, 64, coat) # body
      blob.(43, 76, 34, 48, cream) # belly
      blob.(32, 118, 24, 13, dark) # feet
      blob.(64, 118, 24, 13, dark)
      curve.(coat, [24, 38], [30, 0], [56, 24]) # ears
      curve.(coat, [96, 38], [90, 0], [64, 24])
      curve.(dark, [33, 28], [33, 9], [47, 23])
      curve.(dark, [87, 28], [87, 9], [73, 23])
      blob.(18, 16, 84, 62, coat) # head
      curve.(cream, [20, 50], [34, 54, 48, 58, 60, 74], [72, 58, 86, 54, 100, 50],
        [96, 72, 78, 82, 60, 82], [42, 82, 24, 72, 20, 50]) # cheeks
      parts[:eyes] = [blob.(40, 36, 10, 13, dark), blob.(70, 36, 10, 13, dark)]
      parts[:glints] = [blob.(42, 38, 4, 4, "#ffffff"), blob.(72, 38, 4, 4, "#ffffff")]
      parts[:shut] = [blob.(38, 41, 14, 3, dark), blob.(68, 41, 14, 3, dark)]
      parts[:shut].each(&:hide)
      blob.(27, 55, 13, 7, "#f59a8b") # blush
      blob.(80, 55, 13, 7, "#f59a8b")
      blob.(54, 58, 12, 8, dark) # nose
      parts[:mouth] = blob.(53, 67, 14, 11, "#8a2b22")
      parts[:mouth].hide
    end
    parts
  end

  def fox_shout(f, open)
    open ? f[:mouth].show : f[:mouth].hide
  end

  def fox_blink(f, shut)
    return if f[:blinking] == shut

    f[:blinking] = shut
    (f[:eyes] + f[:glints]).each { |e| shut ? e.hide : e.show }
    f[:shut].each { |e| shut ? e.show : e.hide }
  end

  # The foxes' ambient life: blink now and then; hop when told to. Only what changes is touched,
  # so a quiet frame costs next to nothing.
  def wake_foxes(foxes)
    @hop_frames = 0
    @fox_clock = animate(24) do |frame|
      foxes.each_with_index do |f, i|
        fox_blink(f, (frame + i * 29) % 90 < 3)
      end
      if @hop_frames.positive?
        @hop_frames -= 1
        foxes.each_with_index do |f, i|
          lift = (Math.sin((@hop_frames + i * 4) / 3.0).abs * 16).round
          f[:slot].move(f[:home][0], f[:home][1] - lift)
        end
        foxes.each { |f| f[:slot].move(*f[:home]) } if @hop_frames.zero?
      end
    end
  end

  def hop!(frames = 28)
    @hop_frames = frames
  end

  # A strip of bacon, in a placed slot of its own so it falls with one `move`.
  def bacon(left, top, k: 1.0)
    stack(left: left, top: top, width: (64 * k).ceil, height: (26 * k).ceil) do
      shape(fill: BACON, strokewidth: 0) do
        move_to 2 * k, 10 * k
        curve_to 14 * k, 0, 26 * k, 18 * k, 38 * k, 8 * k
        curve_to 48 * k, 0, 56 * k, 6 * k, 62 * k, 4 * k
        line_to 62 * k, 16 * k
        curve_to 56 * k, 18 * k, 48 * k, 12 * k, 38 * k, 20 * k
        curve_to 26 * k, 30 * k, 14 * k, 12 * k, 2 * k, 22 * k
        line_to 2 * k, 10 * k
      end
      shape(fill: BACON_FAT, strokewidth: 0) do
        move_to 4 * k, 15 * k
        curve_to 15 * k, 7 * k, 26 * k, 23 * k, 38 * k, 13 * k
        curve_to 48 * k, 6 * k, 56 * k, 11 * k, 61 * k, 9 * k
        line_to 61 * k, 12 * k
        curve_to 56 * k, 14 * k, 48 * k, 9 * k, 38 * k, 16 * k
        curve_to 26 * k, 26 * k, 15 * k, 10 * k, 4 * k, 18 * k
      end
    end
  end

  # ---------------------------------------------------------------- page one: the front door

  def front_door
    @keep = Keepsake.load
    Chime.muted = @keep["muted"]
    background PAPER..PAPER_DEEP

    # bacon drifting down behind everything
    srand(7)
    @strips = Array.new(9) do |i|
      k = 0.6 + rand * 0.6
      x = (i * 113 + rand(60)) % 960
      y = rand(700) - 60
      { slot: bacon(x, y, k: k), x: x, y: y.to_f, speed: 0.6 + rand * 1.1, sway: rand * 6.28 }
    end
    @drift = animate(30) do |frame|
      @strips.each do |s|
        s[:y] += s[:speed]
        s[:y] = -40.0 if s[:y] > 690
        s[:slot].move((s[:x] + Math.sin(frame / 25.0 + s[:sway]) * 10).round, s[:y].round)
      end
    end

    stack(left: 0, top: 34, width: 1000) do
      para "Try Ruby!", font: CHEWY, size: 100, stroke: RUBY_DEEP, align: "center", margin: 0,
        left: 5, top: 6, width: 1000
      para "Try Ruby!", font: CHEWY, size: 100, stroke: RUBY, align: "center", margin: 0, width: 1000
      para "a little room where Ruby talks back.  two foxes live here too.",
        size: 25, stroke: INK_SOFT, align: "center", margin: [0, 10, 0, 0]
    end

    @big_foxes = [
      fox(318, 292, k: 1.45, coat: FOX),
      fox(526, 342, k: 1.1, coat: FOX_RED, mirror: true)
    ]
    # the speech bubble, and its little tail pointing at the small fox
    stack(left: 664, top: 262, width: 280, height: 92) do
      background CARD, curve: 24
      border INK, strokewidth: 3, curve: 24
      @shout = para "chunky bacon!", font: CHEWY, size: 30, stroke: RUBY, align: "center", margin: [0, 24, 0, 0]
    end
    speech_tail([704, 352.5], [666, 380], [732, 352.5], [706, 348, 24, 5.5], 3)
    wake_foxes(@big_foxes)

    shouts = ["chunky bacon!", "come in, come in!", "we have a console.", "it's warm in here.", "CHUNKY BACON!"]
    every(2.4) do |n|
      line = shouts[(n + 1) % shouts.size]
      @shout.text = line
      @big_foxes.each { |f| fox_shout(f, line.upcase == line) }
      hop!(18) if line.upcase == line
    end

    done = Array(@keep["done"]).size
    label = done.zero? ? "Come in and try!" : "Carry on: lesson #{[@keep["lesson"].to_i + 1, LESSONS.size].min}"
    label = "Back to the playground!" if done == LESSONS.size
    big_button(label, left: 340, top: 530, width: 320) do
      @keep["mode"] = done == LESSONS.size ? "play" : "lessons"
      Keepsake.save(@keep)
      visit "/try"
    end
    stack(left: 0, top: 600, width: 1000) do
      skip = link(done.zero? ? "or skip the lessons and just play" : "or just play") do
        @keep["mode"] = "play"
        Keepsake.save(@keep)
        visit "/try"
      end
      progress_note = done.positive? && done < LESSONS.size ? "   (#{done} of #{LESSONS.size} lessons done)" : ""
      para skip, progress_note, size: 17, stroke: INK_SOFT, align: "center", margin: 0
    end

    para "for _why, wherever you are.  made with Shoes, on Scarpe.", size: 15, stroke: INK_SOFT,
      align: "center", left: 0, top: 646, width: 1000, margin: 0
  end

  # The little tail of a speech bubble, from two points on its border out to a tip. A patch of
  # card over the border between them makes the tail and the bubble one shape.
  def speech_tail(from, tip, to, patch, thick)
    shape(fill: CARD, stroke: INK, strokewidth: thick) do
      move_to(*from)
      line_to(*tip)
      line_to(*to)
    end
    rect(*patch, fill: CARD, strokewidth: 0)
  end

  # A fat, friendly button: a real one (so a screen reader, Tab and Return all find it), in ruby
  # and Chewy, on a darker slab that makes it look thick enough to press.
  def big_button(label, left:, top:, width:, &action)
    stack(left: left, top: top + 6, width: width, height: 58) { background RUBY_DEEP, curve: 8 }
    stack(left: left, top: top, width: width, height: 58) do
      button(label, width: width, height: 58, color: RUBY, stroke: CARD, font: CHEWY, size: 30) do
        Chime.play(784, 1047, seconds: 0.08)
        action.call
      end
    end
  end

  # ---------------------------------------------------------------- page two: the console room

  def console_room
    @keep = Keepsake.load
    Chime.muted = @keep["muted"]
    @lesson = [@keep["lesson"].to_i, LESSONS.size - 1].min
    @done = Array(@keep["done"])
    @playing = @keep["mode"] == "play" || @done.size == LESSONS.size && @keep["mode"] != "lessons"
    @history = []
    @history_at = 0
    @pending = +""
    @line_no = 1
    background PAPER..PAPER_DEEP

    # -- the header: a title, the path of lesson dots, and a way home
    stack(left: 20, top: 10, width: 400, height: 56) do
      para "Try Ruby!", font: CHEWY, size: 38, stroke: RUBY, margin: 0
    end
    @dots_at = 250
    @dots = LESSONS.each_index.map do |i|
      dot = oval(@dots_at + i * 19, 28, 13, fill: PAPER, stroke: INK_SOFT, strokewidth: 2)
      dot.click { go_to(i) }
      dot
    end
    @ring = oval(@dots_at - 3, 25, 19, fill: rgb(0, 0, 0, 0), stroke: RUBY, strokewidth: 3)
    stack(left: 670, top: 18, width: 310) do
      @sound_link = para "", size: 16, align: "right", margin: 0
    end
    paint_sound_link

    # -- the console
    stack(left: 16, top: 72, width: 596, height: 592) do
      background PLUM, curve: 16
      @log = stack(left: 10, top: 10, width: 576, height: 522, scroll: true) {}
      stack(left: 10, top: 540, width: 576, height: 44) do
        background PLUM_LIGHT, curve: 10
        @prompt = para ">>", font: MONO, size: 16, stroke: PROMPT, left: 12, top: 11, margin: 0
        @input = edit_line(left: 48, top: 5, width: 516, font: MONO, stroke: CHALK, fill: PLUM_LIGHT,
          border_color: PLUM_LIGHT)
      end
    end
    @input.finish = proc { |field| take_line(field.text) }

    # -- the lesson card
    @card = stack(left: 628, top: 72, width: 356, height: 300) {}

    # -- the foxes' corner, with their speech bubble
    @den = stack(left: 628, top: 380, width: 356, height: 104) do
      stack(left: 120, top: 8, width: 236, height: 70) do
        background CARD, curve: 16
        border INK, strokewidth: 2, curve: 16
        @said = para "", size: 17, margin: [12, 8, 10, 6]
      end
      speech_tail([121, 30], [98, 46], [121, 48], [119.5, 31.5, 4.5, 15], 2)
    end
    @little_foxes = [fox(630, 390, k: 0.56, coat: FOX), fox(686, 408, k: 0.46, coat: FOX_RED, mirror: true)]
    wake_foxes(@little_foxes)

    # -- the canvas the console draws on
    stack(left: 628, top: 492, width: 356, height: 172) do
      background CARD, curve: 12
      border INK_SOFT, strokewidth: 2, curve: 12
    end
    @canvas = stack(left: 631, top: 495, width: 350, height: 166) {}
    fresh_pens
    @canvas_label = para "the canvas", size: 13, stroke: INK_SOFT, left: 900, top: 644, margin: 0

    @sandbox = Sandbox.new(self, @canvas)

    keypress do |key|
      case key
      when :escape then drop_line
      when :control_p, :alt_up, :up then walk_history(-1)
      when :control_n, :alt_down, :down then walk_history(1)
      when :control_l then @log.clear
      end
    end

    greet
    show_card
    @input.focus
  end

  # ---------------------------------------------------------------- the console at work

  def greet
    name = @keep["name"]
    say_line "Try Ruby! Type Ruby next to the >> and press Return.", SAID
    say_line "Type help for a hand. Click any code in the card to paste it.", SAID
    say_line ""
    fox_say(name ? "Welcome back, #{name}!" : "Hello! We're the foxes. Try the card up there!")
  end

  # A line of the console's log. Old lines leave so the log stays quick.
  def say_line(text, colour = CHALK)
    @log.append do
      para text, font: MONO, size: 14, stroke: colour, margin: [6, 1, 6, 1]
    end
    @log.contents.first.remove while @log.contents.size > 240
  end

  def scroll_log
    timer(0) { @log.scroll_top = @log.scroll_max }
  end

  def fox_say(text, shout: false)
    @said.replace(*pieces(text))
    @little_foxes&.each { |f| fox_shout(f, shout) }
  end

  def take_line(line)
    @input.text = ""
    @history << line unless line.strip.empty? || @history.last == line
    @history_at = @history.size
    say_line("#{@pending.empty? ? ">>" : ".."} #{line}", PROMPT)
    return scroll_log if command(line)

    code = @pending.empty? ? line : "#{@pending}\n#{line}"
    return scroll_log if code.strip.empty?

    answer = evaluate(code)
    if answer.nil?
      # Ruby wants more (a def with no end yet): wait for the next line
      @pending = code
      @prompt.text = ".."
      return scroll_log
    end

    @pending = +""
    @prompt.text = ">>"
    report(answer)
    react(answer)
    scroll_log
  end

  # Runs code in the sandbox, drawing on the canvas. Answers nil when the code is unfinished.
  def evaluate(code)
    value = error = nil
    begin
      __on_canvas do
        Timeout.timeout(3) { value = @sandbox.__run(code, @line_no) }
      end
    rescue SyntaxError => e
      return nil if unfinished?(e)

      error = e
    rescue Timeout::Error
      error = Timeout::Error.new("that took more than 3 seconds, so the foxes stopped it. (An endless loop?)")
    rescue StandardError, ScriptError, SystemStackError, Sandbox::NoLeaving => e
      error = e
    end
    @line_no += code.count("\n") + 1
    Answer.new(code: code, value: value, error: error, output: @sandbox.__take_said, sandbox: @sandbox)
  end

  # Whether Ruby stopped only because the code ends too soon (a def waiting for its end, an open
  # bracket or string). Worded for both parsers: parse.y (Ruby 3.3) and Prism (3.4 and on).
  def unfinished?(error)
    error.message.match?(/unexpected end-of-input|meets end of file|expected an `end`|to close the|to end with/)
  end

  def report(answer)
    answer.output.each_line { |l| say_line(l.chomp, SAID) }
    if answer.ok?
      say_line("=> #{look_of(answer.value)}", RESULT)
    else
      e = answer.error
      kind = e.is_a?(Timeout::Error) ? "Timeout" : e.class.name.split("::").last
      say_line("#{kind}: #{clip(complaint(e), 200)}", OOPS)
    end
  end

  # The one line of an error worth reading. Prism writes a little picture with a caret under the
  # trouble; take the words after the first caret. Sandboxes have no names, so they are "main".
  def complaint(error)
    lines = error.message.lines.map(&:rstrip)
    caret = lines.find { |l| l.match?(/\|\s*\^+ /) }
    text = caret ? caret.sub(/.*?\^+\s*/, "") : lines.first.to_s
    text.sub(/\A\(console\):\d+:\s*/, "")
      .gsub(/(an instance of )?(#<(Class|Sandbox):0x\h+>|Sandbox\b)/, "main")
      .strip
  end

  # How a value looks after "=>". Shoes things just say what they are.
  def look_of(value)
    text = case value
    when Shoes::Drawable then "#<Shoes::#{value.class.name.split("::").last}>"
    when Sandbox then "main"
    else value.inspect
    end
    clip(text, 400)
  rescue StandardError
    "#<#{value.class}>"
  end

  def clip(text, max) = text.length > max ? "#{text[0, max]}..." : text

  def drop_line
    say_line("#{@pending.empty? ? ">>" : ".."} #{@input.text}  (dropped)", INK_SOFT) unless @input.text.empty? && @pending.empty?
    @pending = +""
    @prompt.text = ">>"
    @input.text = ""
    scroll_log
  end

  def walk_history(step)
    return if @history.empty?

    @history_at = (@history_at + step).clamp(0, @history.size)
    @input.text = @history[@history_at] || ""
  end

  # Shoes starts every pen at black. The canvas starts with ruby and ink, which is friendlier.
  def fresh_pens
    @canvas.fill(RUBY)
    @canvas.stroke(INK)
    @canvas.strokewidth(1)
  end

  # Runs a block with the canvas as the slot things are drawn in. The sandbox's timers use it.
  def __on_canvas(&block)
    @canvas.append(&block)
  end

  def __timer_trouble(error)
    say_line("#{error.class.name.split("::").last} in a timer: #{clip(complaint(error), 160)} (so it stopped)", OOPS)
    scroll_log
  end

  # The console's own words. Answers true when the line was one of them.
  def command(line)
    case line.strip
    when "help"
      [
        "The console knows a few words of its own:",
        "  next / back    walk through the lessons",
        "  lessons        back to the lessons     play   the playground",
        "  clear          clear the log and the canvas",
        "  reset          forget every variable and method",
        "  mute           the chimes on or off",
        "Escape drops a line. Ctrl-P and Ctrl-N walk your history.",
        "Everything else is Ruby!"
      ].each { |l| say_line(l, SAID) }
    when "next" then go_to(@lesson + 1)
    when "back" then go_to(@lesson - 1)
    when "lessons" then @playing = false; save_progress; show_card
    when "play" then @playing = true; save_progress; show_card
    when "clear"
      @log.clear
      @sandbox.clear
    when "reset"
      @sandbox.clear
      @sandbox = Sandbox.new(self, @canvas)
      fresh_pens
      say_line("All forgotten. A fresh start, like new snow.", SAID)
    when "mute" then toggle_sound
    when "why", "_why"
      say_line("why? because. (the foxes whisper it)", SAID)
      fox_say("because!", shout: true)
    else
      return false
    end
    true
  end

  # ---------------------------------------------------------------- lessons, praise and the card

  def react(answer)
    lesson = LESSONS[@lesson]
    if !@playing && lesson.check.(answer)
      pass_lesson(answer)
    elsif answer.ok? && answer.value.to_s.downcase.tr("_", " ").include?("chunky bacon")
      Chime.yay
      hop!
      fox_say("CHUNKY BACON!", shout: true)
    elsif answer.ok?
      fox_say(QUIPS.sample)
    else
      Chime.boop
      fox_say(PUZZLED.sample)
    end
  end

  def pass_lesson(answer)
    if @lesson == 1
      @keep["name"] = answer.value.strip[0, 24]
      @keep["name"] = nil if @keep["name"].empty?
    end
    @done |= [@lesson]
    cheer = fill_in(LESSONS[@lesson].cheer, answer)
    last = @lesson == LESSONS.size - 1
    say_line("  * #{last ? "every lesson done!" : "lesson #{@lesson + 1} done"} *", PROMPT)
    fox_say(cheer, shout: cheer.include?("!!"))
    hop!
    if last
      Chime.fanfare
      bacon_rain
      @playing = true
      save_progress
      paint_dots
      timer(1.2) { show_card }
    else
      Chime.yay
      @lesson += 1
      save_progress
      paint_dots
      timer(0.9) { show_card }
    end
  end

  def fill_in(text, answer = nil)
    name = @keep["name"] || "Jimmy"
    text.gsub("%{name}", name).gsub("%{quoted}", name.inspect)
      .gsub("%{method}", answer&.value.is_a?(Symbol) ? answer.value.to_s : "shout")
  end

  def go_to(index)
    @playing = false
    @lesson = index.clamp(0, LESSONS.size - 1)
    save_progress
    show_card
  end

  def save_progress
    @keep["lesson"] = @lesson
    @keep["done"] = @done.sort
    @keep["mode"] = @playing ? "play" : "lessons"
    Keepsake.save(@keep)
  end

  def paint_dots
    @dots.each_with_index do |dot, i|
      dot.style(fill: @done.include?(i) ? RUBY : PAPER, stroke: @done.include?(i) ? RUBY_DEEP : INK_SOFT)
    end
    if @playing
      @ring.hide
    else
      @ring.show
      @ring.move(@dots_at - 3 + @lesson * 19, 25)
    end
  end

  # Prose with `code` in backticks, as a list of para pieces.
  def pieces(text)
    text.split("`").each_with_index.map { |bit, i| i.odd? ? code(bit, stroke: RUBY_DEEP) : bit }
  end

  # A dark chip with code in it; clicking it pastes the code at the prompt.
  def code_chip(text)
    lines = text.length > 38 ? 2 : 1
    stack(width: 320, margin: [0, 8, 0, 4]) do
      background PLUM, curve: 10
      para text, font: MONO, size: 14, stroke: PROMPT, margin: [12, 8, 12, 9]
      click do
        @input.text = text
        @input.focus
      end
    end
    lines
  end

  def show_card
    paint_dots
    @card.clear do
      background CARD, curve: 16
      border INK, strokewidth: 2, curve: 16
      stack(margin: [18, 14, 18, 10]) do
        @playing ? playground_card : lesson_card
      end
    end
  end

  def lesson_card
    lesson = LESSONS[@lesson]
    para "LESSON #{@lesson + 1} OF #{LESSONS.size}", size: 13, stroke: INK_SOFT, margin: 0
    para lesson.title, font: CHEWY, size: 28, stroke: RUBY, margin: [0, 0, 0, 4]
    para(*pieces(fill_in(lesson.text)), size: 17, margin: [0, 0, 0, 2])
    code_chip(fill_in(lesson.try))
    flow(margin_top: 4) do
      para link("< back") { go_to(@lesson - 1) }, size: 15, margin: [0, 0, 16, 0] if @lesson.positive?
      para link("skip >") { go_to(@lesson + 1) }, size: 15, margin: [0, 0, 16, 0] if @lesson < LESSONS.size - 1
      para "(click the code to paste it)", size: 14, stroke: INK_SOFT, margin: 0
    end
  end

  def playground_card
    para "THE PLAYGROUND", size: 13, stroke: INK_SOFT, margin: 0
    para "Anything goes", font: CHEWY, size: 28, stroke: RUBY, margin: [0, 0, 0, 2]
    para "Click one, change it, press Return.", size: 16, margin: [0, 0, 0, 4]
    stack(height: 160, scroll: true) do
      PLAYTHINGS.each do |thing|
        para link(thing) { @input.text = thing; @input.focus }, font: MONO, size: 12, margin: [0, 3, 0, 3]
      end
    end
    para link("back to the lessons") { command("lessons") }, size: 15, margin: [0, 6, 0, 0]
  end

  # The grand finale: bacon rains over the canvas.
  def bacon_rain
    @sandbox.clear
    srand
    strips = []
    @canvas.append do
      strips = Array.new(10) { |i| { slot: bacon(i * 34 - 10, -30 - rand(120), k: 0.7), y: -30.0 - rand(120), x: i * 34 - 10, v: 2 + rand * 2 } }
    end
    rain = animate(30) do |frame|
      strips.each do |s|
        s[:y] += s[:v]
        s[:slot].move(s[:x], s[:y].round) if s[:y] < 170
      end
      if frame > 120
        rain.stop
        @canvas.clear
      end
    end
  end

  def paint_sound_link
    @sound_link.replace(
      link(Chime.muted ? "sound: off" : "sound: on") { toggle_sound }, "     ",
      link("front door") { visit "/" }
    )
  end

  def toggle_sound
    Chime.muted = !Chime.muted
    @keep["muted"] = Chime.muted
    Keepsake.save(@keep)
    paint_sound_link
  end
end
