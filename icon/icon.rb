# The Try Ruby! icon: a fox on a plum console tile, with a prompt. Drawn by Scarpe itself.
#
#   ./scarpe.sh peek icon/icon.rb --shot icon/square.png
#   convert icon/square.png \( -size 1024x1024 xc:none -fill white \
#     -draw "roundrectangle 100,100 923,923 185,185" \) -compose DstIn -composite icon/icon.png
#
# (`magick` in place of `convert` with ImageMagick 7.) The tile sits on macOS's icon grid: 824 px,
# 100 px in from each edge.

FOX = "#e8702a"
CARD = "#fffaf0"

Shoes.app(title: "Try Ruby! icon", width: 1024, height: 1024, resizable: false) do
  background white

  # the same fox as the app's (try_ruby.rb), drawn at any size
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

  nostroke
  fill "#3b3046".."#241c2b"
  rect 100, 100, 824, 824, 185
  # the console's prompt, and a line of ruby-red code
  para ">>", font: "monospace", size: 120, stroke: "#ffcf5c", left: 170, top: 150, margin: 0
  rect 380, 205, 200, 44, 22, fill: "#cc342d"
  rect 600, 205, 110, 44, 22, fill: "#9be08a"
  fox(232, 330, k: 4.3, coat: FOX)
end
