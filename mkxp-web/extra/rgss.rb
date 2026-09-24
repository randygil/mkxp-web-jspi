module RPG
  # WEB PORT (VX): modern RGSS scripts (param add-on scripts etc.) reopen the item classes with a
  # VXAce-style hierarchy — `class RPG::Armor < RPG::BaseItem`, `RPG::Skill <
  # RPG::UsableItem`, etc. mruby 2.1.2 INFINITE-LOOPS on a superclass mismatch
  # (instead of raising TypeError), so the shim MUST declare the same parents the
  # game expects, or boot hangs the moment those classes are reopened. Define the
  # base classes here and give Skill/Item/Weapon/Armor the matching superclass below.
  class BaseItem;   end
  class UsableItem < BaseItem
    # RGSS2 skill/item shared attributes the XP-shaped shim below lacks. Marshal
    # sets the @ivars from Data/Skills.rvdata etc.; these expose them so param add-on scripts
    # that `alias ... base_damage` / read the damage formula at load don't crash.
    attr_accessor :scope, :occasion, :animation_id, :base_damage, :variance,
                  :atk_f, :spi_f, :physical_attack, :damage_to_mp, :absorb_damage,
                  :ignore_defense, :element_set, :plus_state_set, :minus_state_set,
                  :mp_cost, :hit, :speed, :hp_recovery, :mp_recovery,
                  :hp_recovery_rate, :mp_recovery_rate, :parameter_type,
                  :parameter_points, :common_event_id
    # RGSS2 scope/occasion predicates. These live in the VX runtime's RPG::UsableItem
    # (not the editable game scripts), so a game that strips them relies on the engine
    # providing them. Absent here, every skill/item action crashed the battle at
    # Game_BattleAction / the sideview battle system's target_decision. @scope 0-11, @occasion 0-3.
    def for_opponent?;    [1, 2, 3, 4, 5, 6].include?(@scope);  end
    def for_friend?;      [7, 8, 9, 10, 11].include?(@scope);   end
    def for_dead_friend?; [9, 10].include?(@scope);             end
    def for_user?;        @scope == 11;                         end
    def for_one?;         [1, 3, 7, 9, 11].include?(@scope);    end
    def for_two?;         @scope == 4;                          end
    def for_three?;       @scope == 5;                          end
    def for_random?;      [3, 4, 5].include?(@scope);           end
    def dual?;            @scope == 6;                          end
    def for_all?;         [2, 8, 10].include?(@scope);          end
    def need_selection?;  [1, 7, 9].include?(@scope);           end
    def battle_ok?;       [0, 1].include?(@occasion);           end
    def menu_ok?;         [0, 2].include?(@occasion);           end
  end

  module Cache
    @cache = {}
    def self.load_bitmap(folder_name, filename, hue = 0)
      path = folder_name + filename
      if not @cache.include?(path) or @cache[path].disposed?
        if filename != ""
          @cache[path] = Bitmap.new(path)
        else
          @cache[path] = Bitmap.new(32, 32)
        end
      end
      if hue == 0
        @cache[path]
      else
        key = [path, hue]
        if not @cache.include?(key) or @cache[key].disposed?
          @cache[key] = @cache[path].clone
          @cache[key].hue_change(hue)
        end
        @cache[key]
      end
    end
    def self.animation(filename, hue)
      self.load_bitmap("Graphics/Animations/", filename, hue)
    end
    def self.autotile(filename)
      self.load_bitmap("Graphics/Autotiles/", filename)
    end
    def self.battleback(filename)
      self.load_bitmap("Graphics/Battlebacks/", filename)
    end
    def self.battler(filename, hue)
      self.load_bitmap("Graphics/Battlers/", filename, hue)
    end
    def self.character(filename, hue)
      self.load_bitmap("Graphics/Characters/", filename, hue)
    end
    def self.fog(filename, hue)
      self.load_bitmap("Graphics/Fogs/", filename, hue)
    end
    def self.gameover(filename)
      self.load_bitmap("Graphics/Gameovers/", filename)
    end
    def self.icon(filename)
      self.load_bitmap("Graphics/Icons/", filename)
    end
    def self.panorama(filename, hue)
      self.load_bitmap("Graphics/Panoramas/", filename, hue)
    end
    def self.picture(filename)
      self.load_bitmap("Graphics/Pictures/", filename)
    end
    def self.tileset(filename)
      self.load_bitmap("Graphics/Tilesets/", filename)
    end
    def self.title(filename)
      self.load_bitmap("Graphics/Titles/", filename)
    end
    def self.windowskin(filename)
      self.load_bitmap("Graphics/Windowskins/", filename)
    end
    def self.tile(filename, tile_id, hue)
      key = [filename, tile_id, hue]
      if not @cache.include?(key) or @cache[key].disposed?
        @cache[key] = Bitmap.new(32, 32)
        x = (tile_id - 384) % 8 * 32
        y = (tile_id - 384) / 8 * 32
        rect = Rect.new(x, y, 32, 32)
        @cache[key].blt(0, 0, self.tileset(filename), rect)
        @cache[key].hue_change(hue)
      end
      @cache[key]
    end
    def self.clear
      @cache = {}
      GC.start
    end
  end

  class Sprite < ::Sprite
    @@_animations = []
    @@_reference_count = {}
    def initialize(viewport = nil)
      super(viewport)
      @_whiten_duration = 0
      @_appear_duration = 0
      @_escape_duration = 0
      @_collapse_duration = 0
      @_damage_duration = 0
      @_animation_duration = 0
      @_blink = false
    end
    def dispose
      dispose_damage
      dispose_animation
      dispose_loop_animation
      super
    end
    def whiten
      self.blend_type = 0
      self.color.set(255, 255, 255, 128)
      self.opacity = 255
      @_whiten_duration = 16
      @_appear_duration = 0
      @_escape_duration = 0
      @_collapse_duration = 0
    end
    def appear
      self.blend_type = 0
      self.color.set(0, 0, 0, 0)
      self.opacity = 0
      @_appear_duration = 16
      @_whiten_duration = 0
      @_escape_duration = 0
      @_collapse_duration = 0
    end
    def escape
      self.blend_type = 0
      self.color.set(0, 0, 0, 0)
      self.opacity = 255
      @_escape_duration = 32
      @_whiten_duration = 0
      @_appear_duration = 0
      @_collapse_duration = 0
    end
    def collapse
      self.blend_type = 1
      self.color.set(255, 64, 64, 255)
      self.opacity = 255
      @_collapse_duration = 48
      @_whiten_duration = 0
      @_appear_duration = 0
      @_escape_duration = 0
    end
    def damage(value, critical)
      dispose_damage
      if value.is_a?(Numeric)
        damage_string = value.abs.to_s
      else
        damage_string = value.to_s
      end
      bitmap = Bitmap.new(160, 48)
      bitmap.font.name = "Arial Black"
      bitmap.font.size = 32
      bitmap.font.color.set(0, 0, 0)
      bitmap.draw_text(-1, 12-1, 160, 36, damage_string, 1)
      bitmap.draw_text(+1, 12-1, 160, 36, damage_string, 1)
      bitmap.draw_text(-1, 12+1, 160, 36, damage_string, 1)
      bitmap.draw_text(+1, 12+1, 160, 36, damage_string, 1)
      if value.is_a?(Numeric) and value < 0
        bitmap.font.color.set(176, 255, 144)
      else
        bitmap.font.color.set(255, 255, 255)
      end
      bitmap.draw_text(0, 12, 160, 36, damage_string, 1)
      if critical
        bitmap.font.size = 20
        bitmap.font.color.set(0, 0, 0)
        bitmap.draw_text(-1, -1, 160, 20, "CRITICAL", 1)
        bitmap.draw_text(+1, -1, 160, 20, "CRITICAL", 1)
        bitmap.draw_text(-1, +1, 160, 20, "CRITICAL", 1)
        bitmap.draw_text(+1, +1, 160, 20, "CRITICAL", 1)
        bitmap.font.color.set(255, 255, 255)
        bitmap.draw_text(0, 0, 160, 20, "CRITICAL", 1)
      end
      @_damage_sprite = ::Sprite.new(self.viewport)
      @_damage_sprite.bitmap = bitmap
      @_damage_sprite.ox = 80
      @_damage_sprite.oy = 20
      @_damage_sprite.x = self.x
      @_damage_sprite.y = self.y - self.oy / 2
      @_damage_sprite.z = 3000
      @_damage_duration = 40
    end
    def animation(animation, hit)
      dispose_animation
      @_animation = animation
      return if @_animation == nil
      @_animation_hit = hit
      @_animation_duration = @_animation.frame_max
      animation_name = @_animation.animation_name
      animation_hue = @_animation.animation_hue
      bitmap = RPG::Cache.animation(animation_name, animation_hue)
      if @@_reference_count.include?(bitmap)
        @@_reference_count[bitmap] += 1
      else
        @@_reference_count[bitmap] = 1
      end
      @_animation_sprites = []
      if @_animation.position != 3 or not @@_animations.include?(animation)
        for i in 0..15
          sprite = ::Sprite.new(self.viewport)
          sprite.bitmap = bitmap
          sprite.visible = false
          @_animation_sprites.push(sprite)
        end
        unless @@_animations.include?(animation)
          @@_animations.push(animation)
        end
      end
      update_animation
    end
    def loop_animation(animation)
      return if animation == @_loop_animation
      dispose_loop_animation
      @_loop_animation = animation
      return if @_loop_animation == nil
      @_loop_animation_index = 0
      animation_name = @_loop_animation.animation_name
      animation_hue = @_loop_animation.animation_hue
      bitmap = RPG::Cache.animation(animation_name, animation_hue)
      if @@_reference_count.include?(bitmap)
        @@_reference_count[bitmap] += 1
      else
        @@_reference_count[bitmap] = 1
      end
      @_loop_animation_sprites = []
      for i in 0..15
        sprite = ::Sprite.new(self.viewport)
        sprite.bitmap = bitmap
        sprite.visible = false
        @_loop_animation_sprites.push(sprite)
      end
      update_loop_animation
    end
    def dispose_damage
      if @_damage_sprite != nil
        @_damage_sprite.bitmap.dispose
        @_damage_sprite.dispose
        @_damage_sprite = nil
        @_damage_duration = 0
      end
    end
    def dispose_animation
      if @_animation_sprites != nil
        sprite = @_animation_sprites[0]
        if sprite != nil
          @@_reference_count[sprite.bitmap] -= 1
          if @@_reference_count[sprite.bitmap] == 0
            sprite.bitmap.dispose
          end
        end
        for sprite in @_animation_sprites
          sprite.dispose
        end
        @_animation_sprites = nil
        @_animation = nil
      end
    end
    def dispose_loop_animation
      if @_loop_animation_sprites != nil
        sprite = @_loop_animation_sprites[0]
        if sprite != nil
          @@_reference_count[sprite.bitmap] -= 1
          if @@_reference_count[sprite.bitmap] == 0
            sprite.bitmap.dispose
          end
        end
        for sprite in @_loop_animation_sprites
          sprite.dispose
        end
        @_loop_animation_sprites = nil
        @_loop_animation = nil
      end
    end
    def blink_on
      unless @_blink
        @_blink = true
        @_blink_count = 0
      end
    end
    def blink_off
      if @_blink
        @_blink = false
        self.color.set(0, 0, 0, 0)
      end
    end
    def blink?
      @_blink
    end
    def effect?
      @_whiten_duration > 0 or
      @_appear_duration > 0 or
      @_escape_duration > 0 or
      @_collapse_duration > 0 or
      @_damage_duration > 0 or
      @_animation_duration > 0
    end
    def update
      super
      if @_whiten_duration > 0
        @_whiten_duration -= 1
        self.color.alpha = 128 - (16 - @_whiten_duration) * 10
      end
      if @_appear_duration > 0
        @_appear_duration -= 1
        self.opacity = (16 - @_appear_duration) * 16
      end
      if @_escape_duration > 0
        @_escape_duration -= 1
        self.opacity = 256 - (32 - @_escape_duration) * 10
      end
      if @_collapse_duration > 0
        @_collapse_duration -= 1
        self.opacity = 256 - (48 - @_collapse_duration) * 6
      end
      if @_damage_duration > 0
        @_damage_duration -= 1
        case @_damage_duration
        when 38..39
          @_damage_sprite.y -= 4
        when 36..37
          @_damage_sprite.y -= 2
        when 34..35
          @_damage_sprite.y += 2
        when 28..33
          @_damage_sprite.y += 4
        end
        @_damage_sprite.opacity = 256 - (12 - @_damage_duration) * 32
        if @_damage_duration == 0
          dispose_damage
        end
      end
      if @_animation != nil and (Graphics.frame_count % 2 == 0)
        @_animation_duration -= 1
        update_animation
      end
      if @_loop_animation != nil and (Graphics.frame_count % 2 == 0)
        update_loop_animation
        @_loop_animation_index += 1
        @_loop_animation_index %= @_loop_animation.frame_max
      end
      if @_blink
        @_blink_count = (@_blink_count + 1) % 32
        if @_blink_count < 16
          alpha = (16 - @_blink_count) * 6
        else
          alpha = (@_blink_count - 16) * 6
        end
        self.color.set(255, 255, 255, alpha)
      end
      @@_animations.clear
    end
    def update_animation
      if @_animation_duration > 0
        frame_index = @_animation.frame_max - @_animation_duration
        cell_data = @_animation.frames[frame_index].cell_data
        position = @_animation.position
        animation_set_sprites(@_animation_sprites, cell_data, position)
        for timing in @_animation.timings
          if timing.frame == frame_index
            animation_process_timing(timing, @_animation_hit)
          end
        end
      else
        dispose_animation
      end
    end
    def update_loop_animation
      frame_index = @_loop_animation_index
      cell_data = @_loop_animation.frames[frame_index].cell_data
      position = @_loop_animation.position
      animation_set_sprites(@_loop_animation_sprites, cell_data, position)
      for timing in @_loop_animation.timings
        if timing.frame == frame_index
          animation_process_timing(timing, true)
        end
      end
    end
    def animation_set_sprites(sprites, cell_data, position)
      for i in 0..15
        sprite = sprites[i]
        pattern = cell_data[i, 0]
        if sprite == nil or pattern == nil or pattern == -1
          sprite.visible = false if sprite != nil
          next
        end
        sprite.visible = true
        sprite.src_rect.set(pattern % 5 * 192, pattern / 5 * 192, 192, 192)
        if position == 3
          if self.viewport != nil
            sprite.x = self.viewport.rect.width / 2
            sprite.y = self.viewport.rect.height - 160
          else
            sprite.x = 320
            sprite.y = 240
          end
        else
          sprite.x = self.x - self.ox + self.src_rect.width / 2
          sprite.y = self.y - self.oy + self.src_rect.height / 2
          sprite.y -= self.src_rect.height / 4 if position == 0
          sprite.y += self.src_rect.height / 4 if position == 2
        end
        sprite.x += cell_data[i, 1]
        sprite.y += cell_data[i, 2]
        sprite.z = 2000
        sprite.ox = 96
        sprite.oy = 96
        sprite.zoom_x = cell_data[i, 3] / 100.0
        sprite.zoom_y = cell_data[i, 3] / 100.0
        sprite.angle = cell_data[i, 4]
        sprite.mirror = (cell_data[i, 5] == 1)
        sprite.opacity = cell_data[i, 6] * self.opacity / 255.0
        sprite.blend_type = cell_data[i, 7]
      end
    end
    def animation_process_timing(timing, hit)
      if (timing.condition == 0) or
         (timing.condition == 1 and hit == true) or
         (timing.condition == 2 and hit == false)
        if timing.se.name != ""
          se = timing.se
          Audio.se_play("Audio/SE/" + se.name, se.volume, se.pitch)
        end
        case timing.flash_scope
        when 1
          self.flash(timing.flash_color, timing.flash_duration * 2)
        when 2
          if self.viewport != nil
            self.viewport.flash(timing.flash_color, timing.flash_duration * 2)
          end
        when 3
          self.flash(nil, timing.flash_duration * 2)
        end
      end
    end
    def x=(x)
      sx = x - self.x
      if sx != 0
        if @_animation_sprites != nil
          for i in 0..15
            @_animation_sprites[i].x += sx
          end
        end
        if @_loop_animation_sprites != nil
          for i in 0..15
            @_loop_animation_sprites[i].x += sx
          end
        end
      end
      super
    end
    def y=(y)
      sy = y - self.y
      if sy != 0
        if @_animation_sprites != nil
          for i in 0..15
            @_animation_sprites[i].y += sy
          end
        end
        if @_loop_animation_sprites != nil
          for i in 0..15
            @_loop_animation_sprites[i].y += sy
          end
        end
      end
      super
    end
  end

  class Weather
    def initialize(viewport = nil)
      @type = 0
      @max = 0
      @ox = 0
      @oy = 0
      color1 = Color.new(255, 255, 255, 255)
      color2 = Color.new(255, 255, 255, 128)
      @rain_bitmap = Bitmap.new(7, 56)
      for i in 0..6
        @rain_bitmap.fill_rect(6-i, i*8, 1, 8, color1)
      end
      @storm_bitmap = Bitmap.new(34, 64)
      for i in 0..31
        @storm_bitmap.fill_rect(33-i, i*2, 1, 2, color2)
        @storm_bitmap.fill_rect(32-i, i*2, 1, 2, color1)
        @storm_bitmap.fill_rect(31-i, i*2, 1, 2, color2)
      end
      @snow_bitmap = Bitmap.new(6, 6)
      @snow_bitmap.fill_rect(0, 1, 6, 4, color2)
      @snow_bitmap.fill_rect(1, 0, 4, 6, color2)
      @snow_bitmap.fill_rect(1, 2, 4, 2, color1)
      @snow_bitmap.fill_rect(2, 1, 2, 4, color1)
      @sprites = []
      for i in 1..40
        sprite = Sprite.new(viewport)
        sprite.z = 1000
        sprite.visible = false
        sprite.opacity = 0
        @sprites.push(sprite)
      end
    end
    def dispose
      for sprite in @sprites
        sprite.dispose
      end
      @rain_bitmap.dispose
      @storm_bitmap.dispose
      @snow_bitmap.dispose
    end
    def type=(type)
      return if @type == type
      @type = type
      case @type
      when 1
        bitmap = @rain_bitmap
      when 2
        bitmap = @storm_bitmap
      when 3
        bitmap = @snow_bitmap
      else
        bitmap = nil
      end
      for i in 1..40
        sprite = @sprites[i]
        if sprite != nil
          sprite.visible = (i <= @max)
          sprite.bitmap = bitmap
        end
      end
    end
    def ox=(ox)
      return if @ox == ox;
      @ox = ox
      for sprite in @sprites
        sprite.ox = @ox
      end
    end
    def oy=(oy)
      return if @oy == oy;
      @oy = oy
      for sprite in @sprites
        sprite.oy = @oy
      end
    end
    def max=(max)
      return if @max == max;
      @max = [[max, 0].max, 40].min
      for i in 1..40
        sprite = @sprites[i]
        if sprite != nil
          sprite.visible = (i <= @max)
        end
      end
    end
    def update
      return if @type == 0
      for i in 1..@max
        sprite = @sprites[i]
        if sprite == nil
          break
        end
        if @type == 1
          sprite.x -= 2
          sprite.y += 16
          sprite.opacity -= 8
        end
        if @type == 2
          sprite.x -= 8
          sprite.y += 16
          sprite.opacity -= 12
        end
        if @type == 3
          sprite.x -= 2
          sprite.y += 8
          sprite.opacity -= 8
        end
        x = sprite.x - @ox
        y = sprite.y - @oy
        if sprite.opacity < 64 or x < -50 or x > 750 or y < -300 or y > 500
          sprite.x = rand(800) - 50 + @ox
          sprite.y = rand(800) - 200 + @oy
          sprite.opacity = 255
        end
      end
    end
    attr_reader :type
    attr_reader :max
    attr_reader :ox
    attr_reader :oy
  end

  class Map
    def initialize(width, height)
      @tileset_id = 1
      @width = width
      @height = height
      @scroll_type = 0          # VX
      @autoplay_bgm = false
      @bgm = RPG::AudioFile.new
      @autoplay_bgs = false
      @bgs = RPG::AudioFile.new("", 80)
      @disable_dashing = false  # VX
      @encounter_list = []
      @encounter_step = 30
      @parallax_name = ""       # VX
      @parallax_loop_x = false  # VX
      @parallax_loop_y = false  # VX
      @parallax_sx = 0          # VX
      @parallax_sy = 0          # VX
      @parallax_show = false    # VX
      @data = Table.new(width, height, 3)
      @events = {}
    end
    attr_accessor :tileset_id
    attr_accessor :width
    attr_accessor :height
    attr_accessor :scroll_type      # VX
    attr_accessor :autoplay_bgm
    attr_accessor :bgm
    attr_accessor :autoplay_bgs
    attr_accessor :bgs
    attr_accessor :disable_dashing  # VX
    attr_accessor :encounter_list
    attr_accessor :encounter_step
    attr_accessor :parallax_name     # VX
    attr_accessor :parallax_loop_x   # VX
    attr_accessor :parallax_loop_y   # VX
    attr_accessor :parallax_sx       # VX
    attr_accessor :parallax_sy       # VX
    attr_accessor :parallax_show     # VX
    attr_accessor :data
    attr_accessor :events
  end

  class MapInfo
    def initialize
      @name = ""
      @parent_id = 0
      @order = 0
      @expanded = false
      @scroll_x = 0
      @scroll_y = 0
    end
    attr_accessor :name
    attr_accessor :parent_id
    attr_accessor :order
    attr_accessor :expanded
    attr_accessor :scroll_x
    attr_accessor :scroll_y
  end

  class Event
    class Page
      class Condition
        def initialize
          @switch1_valid = false
          @switch2_valid = false
          @variable_valid = false
          @self_switch_valid = false
          @item_valid = false        # VX
          @actor_valid = false       # VX
          @switch1_id = 1
          @switch2_id = 1
          @variable_id = 1
          @variable_value = 0
          @self_switch_ch = "A"
          @item_id = 1               # VX
          @actor_id = 1              # VX
        end
        attr_accessor :switch1_valid
        attr_accessor :switch2_valid
        attr_accessor :variable_valid
        attr_accessor :self_switch_valid
        attr_accessor :item_valid    # VX
        attr_accessor :actor_valid   # VX
        attr_accessor :switch1_id
        attr_accessor :switch2_id
        attr_accessor :variable_id
        attr_accessor :variable_value
        attr_accessor :self_switch_ch
        attr_accessor :item_id       # VX
        attr_accessor :actor_id      # VX
      end

      class Graphic
        def initialize
          @tile_id = 0
          @character_name = ""
          @character_hue = 0
          @character_index = 0     # VX
          @direction = 2
          @pattern = 0
          @opacity = 255
          @blend_type = 0
        end
        attr_accessor :tile_id
        attr_accessor :character_name
        attr_accessor :character_hue
        attr_accessor :character_index   # VX
        attr_accessor :direction
        attr_accessor :pattern
        attr_accessor :opacity
        attr_accessor :blend_type
      end

      def initialize
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @move_type = 0
        @move_speed = 3
        @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true
        @step_anime = false
        @direction_fix = false
        @through = false
        @always_on_top = false
        @priority_type = 0       # VX (0 below / 1 same / 2 above)
        @trigger = 0
        @list = [RPG::EventCommand.new]
      end
      attr_accessor :condition
      attr_accessor :graphic
      attr_accessor :move_type
      attr_accessor :move_speed
      attr_accessor :move_frequency
      attr_accessor :move_route
      attr_accessor :walk_anime
      attr_accessor :step_anime
      attr_accessor :direction_fix
      attr_accessor :through
      attr_accessor :always_on_top
      attr_accessor :priority_type   # VX
      attr_accessor :trigger
      attr_accessor :list
    end

    def initialize(x, y)
      @id = 0
      @name = ""
      @x = x
      @y = y
      @pages = [RPG::Event::Page.new]
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :x
    attr_accessor :y
    attr_accessor :pages
  end

  class EventCommand
    def initialize(code = 0, indent = 0, parameters = [])
      @code = code
      @indent = indent
      @parameters = parameters
    end
    attr_accessor :code
    attr_accessor :indent
    attr_accessor :parameters
  end

  class MoveRoute
    def initialize
      @repeat = true
      @skippable = false
      @wait = false        # VX (wait for move completion)
      @list = [RPG::MoveCommand.new]
    end
    attr_accessor :repeat
    attr_accessor :skippable
    attr_accessor :wait      # VX
    attr_accessor :list
  end

  class MoveCommand
    def initialize(code = 0, parameters = [])
      @code = code
      @parameters = parameters
    end
    attr_accessor :code
    attr_accessor :parameters
  end

  class Actor
    def initialize
      @id = 0
      @name = ""
      @class_id = 1
      @initial_level = 1
      @final_level = 99
      @exp_basis = 30
      @exp_inflation = 30
      @character_name = ""
      @character_hue = 0
      @battler_name = ""
      @battler_hue = 0
      @character_index = 0   # VX
      @face_name = ""        # VX
      @face_index = 0        # VX
      @parameters = Table.new(6,100)
      for i in 1..99
        @parameters[0,i] = 500+i*50
        @parameters[1,i] = 500+i*50
        @parameters[2,i] = 50+i*5
        @parameters[3,i] = 50+i*5
        @parameters[4,i] = 50+i*5
        @parameters[5,i] = 50+i*5
      end
      @weapon_id = 0
      @armor1_id = 0
      @armor2_id = 0
      @armor3_id = 0
      @armor4_id = 0
      @weapon_fix = false
      @armor1_fix = false
      @armor2_fix = false
      @armor3_fix = false
      @armor4_fix = false
      @two_swords_style = false  # VX
      @fix_equipment = false     # VX
      @auto_battle = false       # VX
      @super_guard = false       # VX
      @pharmacology = false      # VX
      @critical_bonus = false    # VX (read every physical attack in Game_Actor#cri)
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :class_id
    attr_accessor :initial_level
    attr_accessor :final_level
    attr_accessor :exp_basis
    attr_accessor :exp_inflation
    attr_accessor :character_name
    attr_accessor :character_hue
    attr_accessor :character_index   # VX
    attr_accessor :face_name         # VX
    attr_accessor :face_index        # VX
    attr_accessor :battler_name
    attr_accessor :battler_hue
    attr_accessor :parameters
    attr_accessor :weapon_id
    attr_accessor :armor1_id
    attr_accessor :armor2_id
    attr_accessor :armor3_id
    attr_accessor :armor4_id
    attr_accessor :weapon_fix
    attr_accessor :armor1_fix
    attr_accessor :armor2_fix
    attr_accessor :armor3_fix
    attr_accessor :armor4_fix
    attr_accessor :two_swords_style  # VX
    attr_accessor :fix_equipment     # VX
    attr_accessor :auto_battle       # VX
    attr_accessor :super_guard       # VX
    attr_accessor :pharmacology      # VX
    attr_accessor :critical_bonus    # VX
  end

  class Class
    class Learning
      def initialize
        @level = 1
        @skill_id = 1
      end
      attr_accessor :level
      attr_accessor :skill_id
    end

    def initialize
      @id = 0
      @name = ""
      @position = 0
      @weapon_set = []
      @armor_set = []
      @element_ranks = Table.new(1)
      @state_ranks = Table.new(1)
      @learnings = []
      @skill_name_valid = false   # VX: use a custom label for the "Skill" battle command?
      @skill_name = ""            # VX: that custom label (read by Window_ActorCommand)
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :position
    attr_accessor :weapon_set
    attr_accessor :armor_set
    attr_accessor :element_ranks
    attr_accessor :state_ranks
    attr_accessor :learnings
    attr_accessor :skill_name_valid
    attr_accessor :skill_name
  end

  class Skill < UsableItem
    def initialize
      @id = 0
      @name = ""
      @icon_name = ""
      @description = ""
      @scope = 0
      @occasion = 1
      @animation1_id = 0
      @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80)
      @common_event_id = 0
      @sp_cost = 0
      @power = 0
      @atk_f = 0
      @eva_f = 0
      @str_f = 0
      @dex_f = 0
      @agi_f = 0
      @int_f = 100
      @hit = 100
      @pdef_f = 0
      @mdef_f = 100
      @variance = 15
      @element_set = []
      @plus_state_set = []
      @minus_state_set = []
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :icon_name
    attr_accessor :description
    attr_accessor :scope
    attr_accessor :occasion
    attr_accessor :animation1_id
    attr_accessor :animation2_id
    attr_accessor :menu_se
    attr_accessor :common_event_id
    attr_accessor :sp_cost
    attr_accessor :power
    attr_accessor :atk_f
    attr_accessor :eva_f
    attr_accessor :str_f
    attr_accessor :dex_f
    attr_accessor :agi_f
    attr_accessor :int_f
    attr_accessor :hit
    attr_accessor :pdef_f
    attr_accessor :mdef_f
    attr_accessor :variance
    attr_accessor :element_set
    attr_accessor :plus_state_set
    attr_accessor :minus_state_set
    # WEB PORT: this Skill class was declared XP-style (icon_name only), but the VX windows
    # (Window_Base#draw_item_name -> draw_icon) read icon_index. The VX save/data carries
    # @icon_index (as Weapon/Armor/State already expose), so the accessor was simply missing
    # -> `undefined method 'icon_index'` -> the battle "Skill" command froze. Read it, default 0.
    def icon_index; @icon_index || 0; end
    # WEB PORT: VX skill battle-use messages. Scene_Battle does `name + skill.message1`
    # and `skill.message2.empty?` when a skill is USED -> missing accessors would raise
    # `undefined method 'message1'` and crash the skill action. Default "" (they call .empty?).
    def message1; @message1 || ""; end
    def message2; @message2 || ""; end
  end

  class Item < UsableItem
    def initialize
      @id = 0
      @name = ""
      @icon_name = ""
      @description = ""
      @scope = 0
      @occasion = 0
      @animation1_id = 0
      @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80)
      @common_event_id = 0
      @price = 0
      @consumable = true
      @parameter_type = 0
      @parameter_points = 0
      @recover_hp_rate = 0
      @recover_hp = 0
      @recover_sp_rate = 0
      @recover_sp = 0
      @hit = 100
      @pdef_f = 0
      @mdef_f = 0
      @variance = 0
      @element_set = []
      @plus_state_set = []
      @minus_state_set = []
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :icon_name
    attr_accessor :description
    attr_accessor :scope
    attr_accessor :occasion
    attr_accessor :animation1_id
    attr_accessor :animation2_id
    attr_accessor :menu_se
    attr_accessor :common_event_id
    attr_accessor :price
    attr_accessor :consumable
    attr_accessor :parameter_type
    attr_accessor :parameter_points
    attr_accessor :recover_hp_rate
    attr_accessor :recover_hp
    attr_accessor :recover_sp_rate
    attr_accessor :recover_sp
    attr_accessor :hit
    attr_accessor :pdef_f
    attr_accessor :mdef_f
    attr_accessor :variance
    attr_accessor :element_set
    attr_accessor :plus_state_set
    attr_accessor :minus_state_set
    # WEB PORT: same as Skill — the battle "Item" command's Window_Item#draw_item ->
    # draw_item_name reads icon_index, absent on this XP-style Item class -> froze. Default 0.
    def icon_index; @icon_index || 0; end
  end

  class Weapon < BaseItem
    def initialize
      @id = 0
      @name = ""
      @icon_name = ""
      @description = ""
      @animation1_id = 0
      @animation2_id = 0
      @price = 0
      @atk = 0
      @pdef = 0
      @mdef = 0
      @str_plus = 0
      @dex_plus = 0
      @agi_plus = 0
      @int_plus = 0
      @element_set = []
      @plus_state_set = []
      @minus_state_set = []
      # VX weapon fields (Marshal fills these from Weapons.rvdata; param add-on scripts
      # read two_handed/fast_attack/etc. and the def/spi/agi params).
      @icon_index = 0
      @animation_id = 0
      @two_handed = false
      @fast_attack = false
      @dual_attack = false
      @critical_bonus = false
      @def = 0
      @spi = 0
      @agi = 0
      @hit = 95      # VX weapon hit% — WAS MISSING. Marshal fills @hit from Weapons.rvdata,
                     # but with no reader, weapon.hit fell through to a note-tag stat add-on
                     # (its #hit) = 0 for an empty note -> actor.hit = 0 -> 100% miss.
      @auto_hp_recover = false   # VX (read on weapons by the equip-feature aggregator; no reader/module -> would crash)
      @state_set = []
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :icon_name
    attr_accessor :description
    attr_accessor :animation1_id
    attr_accessor :animation2_id
    attr_accessor :price
    attr_accessor :atk
    attr_accessor :pdef
    attr_accessor :mdef
    attr_accessor :str_plus
    attr_accessor :dex_plus
    attr_accessor :agi_plus
    attr_accessor :int_plus
    attr_accessor :element_set
    attr_accessor :plus_state_set
    attr_accessor :minus_state_set
    attr_accessor :icon_index      # VX
    attr_accessor :animation_id    # VX
    attr_accessor :two_handed      # VX
    attr_accessor :fast_attack     # VX
    attr_accessor :dual_attack     # VX
    attr_accessor :critical_bonus  # VX
    attr_accessor :def             # VX
    attr_accessor :spi             # VX
    attr_accessor :agi             # VX
    attr_accessor :hit             # VX  (was missing -> weapon.hit=0 -> all attacks missed)
    attr_accessor :auto_hp_recover # VX  (read by the equip-feature aggregator; no reader/module -> crash)
    attr_accessor :state_set       # VX
  end

  class Armor < BaseItem
    def initialize
      @id = 0
      @name = ""
      @icon_name = ""
      @description = ""
      @kind = 0
      @auto_state_id = 0
      @price = 0
      @pdef = 0
      @mdef = 0
      @eva = 0
      @str_plus = 0
      @dex_plus = 0
      @agi_plus = 0
      @int_plus = 0
      @guard_element_set = []
      @guard_state_set = []
      # VX armor fields (Marshal fills these from Armors.rvdata).
      @icon_index = 0
      @atk = 0
      @def = 0
      @spi = 0
      @agi = 0
      @element_set = []
      @state_set = []
      @prevent_critical = false   # VX (were missing readers -> silent note-tag-only / crash)
      @half_mp_cost = false        # VX
      @double_exp_gain = false     # VX
      @auto_hp_recover = false     # VX
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :icon_name
    attr_accessor :description
    attr_accessor :kind
    attr_accessor :auto_state_id
    attr_accessor :price
    attr_accessor :pdef
    attr_accessor :mdef
    attr_accessor :eva
    attr_accessor :str_plus
    attr_accessor :dex_plus
    attr_accessor :agi_plus
    attr_accessor :int_plus
    attr_accessor :guard_element_set
    attr_accessor :guard_state_set
    attr_accessor :icon_index    # VX
    attr_accessor :atk           # VX
    attr_accessor :def           # VX
    attr_accessor :spi           # VX
    attr_accessor :agi           # VX
    attr_accessor :element_set   # VX
    attr_accessor :state_set     # VX
    # WEB PORT: VX armor feature flags (editor checkboxes, Marshal-filled). Missing readers made
    # prevent_critical/half_mp_cost/double_exp_gain silently read only note-tags (a note-tag stat add-on aliases
    # them, but the @ivar had no reader), and auto_hp_recover raise NoMethodError on the turn-end
    # HP-regen check. Same class as weapon.hit. Expose all four.
    attr_accessor :prevent_critical  # VX
    attr_accessor :half_mp_cost      # VX
    attr_accessor :double_exp_gain   # VX
    attr_accessor :auto_hp_recover   # VX
  end

  class Enemy
    # RGSS2 nested drop-item record (Marshal'd from Data/Enemies.rvdata).
    class DropItem
      # WEB PORT: some VX games Marshal a custom drop layout (@item_id/@weapon_id/@armor_id)
      # instead of the stock @database_id; Game_Troop#make_drop_items reads those at victory.
      attr_accessor :kind, :database_id, :denominator, :item_id, :weapon_id, :armor_id
      def initialize; @kind = 0; @database_id = 1; @denominator = 1; @item_id = 0; @weapon_id = 0; @armor_id = 0; end
    end
    class Action
      def initialize
        @kind = 0
        @basic = 0
        @skill_id = 1
        @condition_turn_a = 0
        @condition_turn_b = 1
        @condition_hp = 100
        @condition_level = 1
        @condition_switch_id = 0
        @rating = 5
      end
      attr_accessor :kind
      attr_accessor :basic
      attr_accessor :skill_id
      attr_accessor :condition_turn_a
      attr_accessor :condition_turn_b
      attr_accessor :condition_hp
      attr_accessor :condition_level
      attr_accessor :condition_switch_id
      attr_accessor :rating
      # WEB PORT (VX): VX enemy actions gate on condition_type + condition_param1/param2 (Marshal'd
      # from Data/Enemies.rvdata), not the XP condition_turn_a/b/hp/level/switch_id above.
      # Game_Enemy#conditions_met? reads them every time an enemy picks an
      # action, so enemy turns would crash ("undefined method 'condition_type'") without these.
      attr_accessor :condition_type
      attr_accessor :condition_param1
      attr_accessor :condition_param2
    end

    def initialize
      @id = 0
      @name = ""
      @battler_name = ""
      @battler_hue = 0
      @maxhp = 500
      @maxsp = 500
      @str = 50
      @dex = 50
      @agi = 50
      @int = 50
      @atk = 100
      @pdef = 100
      @mdef = 100
      @eva = 0
      @animation1_id = 0
      @animation2_id = 0
      @element_ranks = Table.new(1)
      @state_ranks = Table.new(1)
      @actions = [RPG::Enemy::Action.new]
      @exp = 0
      @gold = 0
      @item_id = 0
      @weapon_id = 0
      @armor_id = 0
      @treasure_prob = 100
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :battler_name
    attr_accessor :battler_hue
    attr_accessor :maxhp
    attr_accessor :maxsp
    attr_accessor :str
    attr_accessor :dex
    attr_accessor :agi
    attr_accessor :int
    attr_accessor :atk
    attr_accessor :pdef
    attr_accessor :mdef
    attr_accessor :eva
    attr_accessor :animation1_id
    attr_accessor :animation2_id
    attr_accessor :element_ranks
    attr_accessor :state_ranks
    attr_accessor :actions
    attr_accessor :exp
    attr_accessor :gold
    attr_accessor :item_id
    attr_accessor :weapon_id
    attr_accessor :armor_id
    attr_accessor :treasure_prob
    # WEB PORT (VX): the accessors above are XP-shaped (maxsp / pdef / mdef / item_id...), but the
    # target is RPG Maker VX (RGSS2). Data/Enemies.rvdata Marshals VX-named enemy ivars — @maxmp,
    # @def, @spi, @hit, @has_critical, @drop_item1/2 (verified in the data stream) — which have no
    # reader here. Game_Enemy#base_maxmp/#base_def/#base_spi/#base_cri and the drop logic
    # read them, so a battle raised "undefined method 'maxmp'" the instant an
    # enemy was instantiated (Game_Enemy#initialize: `@mp = maxmp`), and def/spi/hit/crit/drops
    # would crash later mid-battle. Marshal.load sets the ivars directly (bypassing initialize), so
    # plain accessors over the loaded values are enough. (`:def` is a valid symbol; enemy.def works.)
    attr_accessor :maxmp
    attr_accessor :def
    attr_accessor :spi
    attr_accessor :hit
    attr_accessor :has_critical
    attr_accessor :drop_item1
    attr_accessor :drop_item2
    attr_accessor :levitate     # VX (floating flag; present in Enemies.rvdata, expose for completeness)
  end

  class Troop
    class Member
      def initialize
        @enemy_id = 1
        @x = 0
        @y = 0
        @hidden = false
        @immortal = false
      end
      attr_accessor :enemy_id
      attr_accessor :x
      attr_accessor :y
      attr_accessor :hidden
      attr_accessor :immortal
    end

    class Page
      class Condition
        def initialize
          @turn_ending = false       # VX: "turn end" trigger (was missing -> froze battle turn)
          @turn_valid = false
          @enemy_valid = false
          @actor_valid = false
          @switch_valid = false
          @turn_a = 0
          @turn_b = 0
          @enemy_index = 0
          @enemy_hp = 50
          @actor_id = 1
          @actor_hp = 50
          @switch_id = 1
        end
        attr_accessor :turn_ending
        attr_accessor :turn_valid
        attr_accessor :enemy_valid
        attr_accessor :actor_valid
        attr_accessor :switch_valid
        attr_accessor :turn_a
        attr_accessor :turn_b
        attr_accessor :enemy_index
        attr_accessor :enemy_hp
        attr_accessor :actor_id
        attr_accessor :actor_hp
        attr_accessor :switch_id
      end

      def initialize
        @condition = RPG::Troop::Page::Condition.new
        @span = 0
        @list = [RPG::EventCommand.new]
      end
      attr_accessor :condition
      attr_accessor :span
      attr_accessor :list
    end

    def initialize
      @id = 0
      @name = ""
      @members = []
      # WEB PORT: was RPG::BattleEventPage (undefined -> NameError). VX's class is RPG::Troop::Page
      # (defined above). Dormant today (Marshal.load bypasses initialize and nothing calls
      # RPG::Troop.new), but fix the latent NameError.
      @pages = [RPG::Troop::Page.new]
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :members
    attr_accessor :pages
  end

  class State
    # RGSS2 State param-rate attributes the XP-shaped body below lacks (Marshal fills
    # the @ivars from Data/States.rvdata; param add-on scripts alias them at load).
    attr_accessor :atk_rate, :def_rate, :spi_rate, :agi_rate, :maxhp_rate,
                  :maxmp_rate, :hp_change_type, :hp_change_value, :hp_change_max,
                  :mp_change_type, :mp_change_value, :mp_change_max, :priority,
                  :reduce_hit_ratio, :offset_by_opposite, :nonresistance,
                  :battle_only, :release_by_damage, :message1, :message2,
                  :message3, :message4
    def initialize
      @id = 0
      @name = ""
      @animation_id = 0
      @restriction = 0
      @nonresistance = false
      @zero_hp = false
      @cant_get_exp = false
      @cant_evade = false
      @slip_damage = false
      @rating = 5
      @hit_rate = 100
      @maxhp_rate = 100
      @maxsp_rate = 100
      @str_rate = 100
      @dex_rate = 100
      @agi_rate = 100
      @int_rate = 100
      @atk_rate = 100
      @pdef_rate = 100
      @mdef_rate = 100
      @eva = 0
      @battle_only = true
      @hold_turn = 0
      @auto_release_prob = 0
      @shock_release_prob = 0
      @guard_element_set = []
      @plus_state_set = []
      @minus_state_set = []
      @state_set = []
      @icon_index = 0
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :animation_id
    attr_accessor :restriction
    attr_accessor :nonresistance
    attr_accessor :zero_hp
    attr_accessor :cant_get_exp
    attr_accessor :cant_evade
    attr_accessor :slip_damage
    attr_accessor :rating
    attr_accessor :hit_rate
    attr_accessor :maxhp_rate
    attr_accessor :maxsp_rate
    attr_accessor :str_rate
    attr_accessor :dex_rate
    attr_accessor :agi_rate
    attr_accessor :int_rate
    attr_accessor :atk_rate
    attr_accessor :pdef_rate
    attr_accessor :mdef_rate
    attr_accessor :eva
    attr_accessor :battle_only
    attr_accessor :hold_turn
    attr_accessor :auto_release_prob
    attr_accessor :shock_release_prob
    attr_accessor :guard_element_set
    attr_accessor :plus_state_set
    attr_accessor :minus_state_set
    attr_accessor :icon_index              # VX: state icon (drawn by Window_Base#draw_actor_state)
    attr_writer :state_set                 # VX: state-membership set (Marshal fills @state_set)
    def state_set; @state_set || []; end   # defensive: nil when data omits it -> [] (avoids nil.include?)
    # WEB PORT: a VX game's element_rate calls state.element_set /
    # state.guard_state_set, but VX RPG::State Marshals neither (they're XP/custom fields). Provide
    # readers that fall back to [] so `state.element_set.include?(id)` is a clean false, not a
    # NoMethodError that freezes the first skill that resolves an element rate mid-battle.
    attr_writer :element_set, :guard_state_set
    def element_set; @element_set || []; end
    def guard_state_set; @guard_state_set || []; end
  end

  class Animation
    class Frame
      def initialize
        @cell_max = 0
        @cell_data = Table.new(0, 0)
      end
      attr_accessor :cell_max
      attr_accessor :cell_data
    end

    class Timing
      def initialize
        @frame = 0
        @se = RPG::AudioFile.new("", 80)
        @flash_scope = 0
        @flash_color = Color.new(255,255,255,255)
        @flash_duration = 5
        @condition = 0
      end
      attr_accessor :frame
      attr_accessor :se
      attr_accessor :flash_scope
      attr_accessor :flash_color
      attr_accessor :flash_duration
      attr_accessor :condition
    end

    def initialize
      @id = 0
      @name = ""
      @animation_name = ""
      @animation_hue = 0
      @position = 1
      @frame_max = 1
      @frames = [RPG::Animation::Frame.new]
      @timings = []
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :animation_name
    attr_accessor :animation_hue
    # WEB PORT (VX): the two accessors above are XP-shaped (a single animation graphic). The target
    # is RPG Maker VX (RGSS2), whose RPG::Animation Marshals @animation1_name/@animation1_hue and
    # @animation2_name/@animation2_hue instead (verified present in Data/Animations.rvdata; the XP
    # @animation_name/@animation_hue are absent). Sprite_Base#load_animation_bitmap
    # reads all four, so the first battle hit-animation raised
    # "undefined method 'animation1_name'". Marshal.load sets the ivars directly, so readers suffice.
    attr_accessor :animation1_name
    attr_accessor :animation1_hue
    attr_accessor :animation2_name
    attr_accessor :animation2_hue
    attr_accessor :position
    attr_accessor :frame_max
    attr_accessor :frames
    attr_accessor :timings
  end

  class Tileset
    def initialize
      @id = 0
      @name = ""
      @tileset_name = ""
      @autotile_names = [""]*7
      @panorama_name = ""
      @panorama_hue = 0
      @fog_name = ""
      @fog_hue = 0
      @fog_opacity = 64
      @fog_blend_type = 0
      @fog_zoom = 200
      @fog_sx = 0
      @fog_sy = 0
      @battleback_name = ""
      @passages = Table.new(384)
      @priorities = Table.new(384)
      @priorities[0] = 5
      @terrain_tags = Table.new(384)
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :tileset_name
    attr_accessor :autotile_names
    attr_accessor :panorama_name
    attr_accessor :panorama_hue
    attr_accessor :fog_name
    attr_accessor :fog_hue
    attr_accessor :fog_opacity
    attr_accessor :fog_blend_type
    attr_accessor :fog_zoom
    attr_accessor :fog_sx
    attr_accessor :fog_sy
    attr_accessor :battleback_name
    attr_accessor :passages
    attr_accessor :priorities
    attr_accessor :terrain_tags
  end

  class CommonEvent
    def initialize
      @id = 0
      @name = ""
      @trigger = 0
      @switch_id = 1
      @list = [RPG::EventCommand.new]
    end
    attr_accessor :id
    attr_accessor :name
    attr_accessor :trigger
    attr_accessor :switch_id
    attr_accessor :list
  end

  class System
    class Words
      def initialize
        @gold = ""
        @hp = ""
        @sp = ""
        @str = ""
        @dex = ""
        @agi = ""
        @int = ""
        @atk = ""
        @pdef = ""
        @mdef = ""
        @weapon = ""
        @armor1 = ""
        @armor2 = ""
        @armor3 = ""
        @armor4 = ""
        @attack = ""
        @skill = ""
        @guard = ""
        @item = ""
        @equip = ""
      end
      attr_accessor :gold
      attr_accessor :hp
      attr_accessor :sp
      attr_accessor :str
      attr_accessor :dex
      attr_accessor :agi
      attr_accessor :int
      attr_accessor :atk
      attr_accessor :pdef
      attr_accessor :mdef
      attr_accessor :weapon
      attr_accessor :armor1
      attr_accessor :armor2
      attr_accessor :armor3
      attr_accessor :armor4
      attr_accessor :attack
      attr_accessor :skill
      attr_accessor :guard
      attr_accessor :item
      attr_accessor :equip
    end

    class TestBattler
      def initialize
        @actor_id = 1
        @level = 1
        @weapon_id = 0
        @armor1_id = 0
        @armor2_id = 0
        @armor3_id = 0
        @armor4_id = 0
      end
      attr_accessor :actor_id
      attr_accessor :level
      attr_accessor :weapon_id
      attr_accessor :armor1_id
      attr_accessor :armor2_id
      attr_accessor :armor3_id
      attr_accessor :armor4_id
    end

    def initialize
      @magic_number = 0
      @party_members = [1]
      @elements = [nil, ""]
      @switches = [nil, ""]
      @variables = [nil, ""]
      @windowskin_name = ""
      @title_name = ""
      @gameover_name = ""
      @battle_transition = ""
      @title_bgm = RPG::AudioFile.new
      @battle_bgm = RPG::AudioFile.new
      @battle_end_me = RPG::AudioFile.new
      @gameover_me = RPG::AudioFile.new
      @cursor_se = RPG::AudioFile.new("", 80)
      @decision_se = RPG::AudioFile.new("", 80)
      @cancel_se = RPG::AudioFile.new("", 80)
      @buzzer_se = RPG::AudioFile.new("", 80)
      @equip_se = RPG::AudioFile.new("", 80)
      @shop_se = RPG::AudioFile.new("", 80)
      @save_se = RPG::AudioFile.new("", 80)
      @load_se = RPG::AudioFile.new("", 80)
      @battle_start_se = RPG::AudioFile.new("", 80)
      @escape_se = RPG::AudioFile.new("", 80)
      @actor_collapse_se = RPG::AudioFile.new("", 80)
      @enemy_collapse_se = RPG::AudioFile.new("", 80)
      @words = RPG::System::Words.new
      @test_battlers = []
      @test_troop_id = 1
      @start_map_id = 1
      @start_x = 0
      @start_y = 0
      @battleback_name = ""
      @battler_name = ""
      @battler_hue = 0
      @edit_map_id = 1
    end
    attr_accessor :magic_number
    attr_accessor :party_members
    attr_accessor :elements
    attr_accessor :switches
    attr_accessor :variables
    attr_accessor :windowskin_name
    attr_accessor :title_name
    attr_accessor :gameover_name
    attr_accessor :battle_transition
    attr_accessor :title_bgm
    attr_accessor :battle_bgm
    attr_accessor :battle_end_me
    attr_accessor :gameover_me
    attr_accessor :cursor_se
    attr_accessor :decision_se
    attr_accessor :cancel_se
    attr_accessor :buzzer_se
    attr_accessor :equip_se
    attr_accessor :shop_se
    attr_accessor :save_se
    attr_accessor :load_se
    attr_accessor :battle_start_se
    attr_accessor :escape_se
    attr_accessor :actor_collapse_se
    attr_accessor :enemy_collapse_se
    attr_accessor :words
    attr_accessor :test_battlers
    attr_accessor :test_troop_id
    attr_accessor :start_map_id
    attr_accessor :start_x
    attr_accessor :start_y
    attr_accessor :battleback_name
    attr_accessor :battler_name
    attr_accessor :battler_hue
    attr_accessor :edit_map_id
  end

  class AudioFile
    def initialize(name = "", volume = 100, pitch = 100)
      @name = name
      @volume = volume
      @pitch = pitch
    end
    attr_accessor :name
    attr_accessor :volume
    attr_accessor :pitch
  end
end

#===========================================================
# WEB PORT SHIM (mkxp-web / mruby) — for games that construct Win32API objects
# Win32API does not exist under mruby. Permissive stub so scripts that
# construct Win32API objects boot instead of raising ArgumentError.
# NOTE: real behaviour (mouse, mp3, INI, clipboard, screenshots) is NOT
# provided — call sites that rely on return values are ported as they surface.
#===========================================================
class Win32API
  # mruby-safe permissive stub. Records the declared RETURN/export type at
  # construction so #call returns a type-appropriate default:
  #   'p'/'P'/'s'/'S' (pointer/string return) -> "" so callers doing
  #      String#unpack / #split / string concat don't TypeError.
  #   everything else ('i','l','v','', unknown) -> Integer 0 (arithmetic/==).
  # Robust to any args (zero args, nil, Array export types). No defined?,
  # no undefined class-var reads.
  def initialize(*args)
    @dll  = (args[0].to_s rescue "")
    @func = (args[1].to_s rescue "")
    ret = args[args.size - 1]
    ret = ret[ret.size - 1] if ret.is_a?(Array) && ret.size > 0
    ret = ret.to_s
    last = (ret.size > 0 ? ret[ret.size - 1, 1] : "")
    @__win32_ret_string = (last == "p" || last == "P" || last == "s" || last == "S")
  end
  def call(*args)
    return "" if @__win32_ret_string
    0
  end
  def Call(*args); call(*args); end
end


#===========================================================
# WEB PORT SHIM — Thread/Mutex (mruby has no real threads).
# Synchronous no-op stubs: Thread.new runs its block inline.
# Enough for boot (BitmapCache/Audio use Thread.critical) — real
# concurrency is not available in the browser single thread.
#===========================================================
class Thread
  def self.critical; false; end
  def self.critical=(v); v; end
  def self.new(*args); yield(*args) if block_given?; allocate; end
  def self.start(*args); yield(*args) if block_given?; allocate; end
  def self.list; []; end
  def self.pass; nil; end
  def self.current; allocate; end
  def join(*); self; end
  def kill; self; end
  def alive?; false; end
  def [](k); nil; end
  def []=(k,v); v; end
end
#===========================================================
# WEB PORT SHIM — ENV (mruby has no environment). Empty hash so ENV["X"]
# returns nil instead of raising "uninitialized constant ENV".
#===========================================================
ENV = {} unless Object.const_defined?(:ENV)

#===========================================================
# WEB PORT SHIM — ObjectSpace.define_finalizer (mruby has no finalizers).
# No-op stubs so save-file loading / object setup don't raise NoMethodError.
#===========================================================
module ObjectSpace
  def self.define_finalizer(*a); a[0]; end
  def self.undefine_finalizer(*a); a[0]; end
  # mruby cannot enumerate live objects. Essentials uses each_object only for
  # best-effort sweeps (hide-all / resize-all / transition-all sprites), so a
  # no-op that yields nothing degrades gracefully instead of raising.
  def self.each_object(klass = nil); 0; end
  # _id2ref (object_id -> object) has no mruby equivalent; behave like a stale
  # reference so WeakRef-style callers treat the object as collected.
  def self._id2ref(id); raise RangeError, "recycled object 0x%x" % id.to_i; end
  def self.garbage_collect(*a); (GC.start rescue nil); nil; end
  def self.count_objects(*a); {}; end
end

#===========================================================
# WEB PORT SHIM — Dir (mruby has no Dir). Benign stubs: listings return [],
# pwd returns ".". Filesystem browsing (gif frame globbing, etc.) degrades
# gracefully instead of raising "uninitialized constant Dir".
#===========================================================
unless Object.const_defined?(:Dir)
  class Dir
    def self.pwd; "."; end
    def self.glob(*a); []; end
    def self.[](*a); []; end
    def self.entries(*a); []; end
    def self.exist?(*a); false; end
    def self.exists?(*a); false; end
    def self.mkdir(*a); nil; end
    def self.chdir(*a); yield if block_given?; end
    def self.foreach(*a); nil; end
  end
end

class Mutex
  def lock; self; end
  def unlock; self; end
  def locked?; false; end
  def synchronize; yield if block_given?; end
  def try_lock; true; end
end


#===========================================================
# WEB PORT SHIM — streaming Zlib::Deflate / Zlib::Inflate + constants.
# The native binding (binding-mruby.cpp) provides the Zlib module plus the
# class methods Zlib::Inflate.inflate / Zlib::Deflate.deflate / Zlib.crc32.
# Essentials' PNG/border code also uses the *streaming* object API
# (Zlib::Deflate.new(9) << data ... finish), so wrap it on top of the native
# one-shot deflate: buffer everything, emit the complete stream on finish.
#===========================================================
module Zlib
  NO_FLUSH            = 0
  SYNC_FLUSH          = 2
  FULL_FLUSH          = 3
  FINISH              = 4
  NO_COMPRESSION      = 0
  BEST_SPEED          = 1
  BEST_COMPRESSION    = 9
  DEFAULT_COMPRESSION = -1

  class Deflate
    def initialize(level = DEFAULT_COMPRESSION, *args); @buf = ""; @level = level; @done = false; end
    def <<(s); @buf += s.to_s if s; self; end
    def deflate(s, flush = NO_FLUSH); @buf += s.to_s if s; ""; end
    def flush(*a); ""; end
    def finish; return "" if @done; @done = true; Zlib::Deflate.deflate(@buf, @level); end
    def close; @buf = ""; nil; end
    def finished?; @done; end
  end

  class Inflate
    def initialize(*args); @buf = ""; end
    def <<(s); @buf += s.to_s if s; self; end
    def inflate(s); @buf += s.to_s if s; ""; end
    def finish; Zlib::Inflate.inflate(@buf); end
    def close; @buf = ""; nil; end
  end
end


#===========================================================
# WEB PORT SHIM — tolerant native Audio + frame-independent BGM.
#
# 1) mkxp's native audio decodes OGG only (Vorbisfile). RGSS games often also reference
#    .wav/.mp3/.mid, which raise SDLError and would crash gameplay. Wrapping the play
#    methods swallows those errors so playback degrades to silence instead of dying.
#    (Convert your audio to OGG to actually hear those files.)
# 2) Arity guard: some games/plugins call Audio.*_play with a 4th `position` argument;
#    the native methods take (name, volume, pitch) only, so forward just the first three.
# 3) Frame-independent BGM: mkxp's OpenAL renders on a main-thread ScriptProcessorNode, so
#    BGM stutters when the main thread blocks (e.g. a synchronous Marshal save, a long map
#    load). Route BGM to the Web Audio player (Audio.web_bgm_*, backed by js/webbgm.js) which
#    plays on the browser's audio thread. Falls back to mkxp's OpenAL if the web_bgm_* engine
#    binding is absent. SE/BGS/ME stay on mkxp's OpenAL (short / less noticeable).
#===========================================================
module Audio
  class << self
    alias __web_se_play  se_play
    alias __web_bgm_play bgm_play
    alias __web_bgs_play bgs_play
    alias __web_me_play  me_play
    # Capture native stop/fade too (before a game reopens module Audio and shadows them).
    alias_method(:__web_bgm_stop, :bgm_stop)   rescue nil
    alias_method(:__web_bgm_fade, :bgm_fade)   rescue nil
    alias_method(:__web_bgs_stop, :bgs_stop)   rescue nil
    alias_method(:__web_bgs_fade, :bgs_fade)   rescue nil
    alias_method(:__web_me_stop,  :me_stop)    rescue nil
    alias_method(:__web_me_fade,  :me_fade)    rescue nil
    alias_method(:__web_se_stop,  :se_stop)    rescue nil
  end

  def self.se_play(*a);  begin; __web_se_play(*a[0,3]);  rescue Exception; end; end
  def self.bgs_play(*a); begin; __web_bgs_play(*a[0,3]); rescue Exception; end; end
  def self.me_play(*a);  begin; __web_me_play(*a[0,3]);  rescue Exception; end; end

  def self.bgm_play(*a)
    begin
      if Audio.respond_to?(:web_bgm_play); web_bgm_play(*a[0,3]); else __web_bgm_play(*a[0,3]); end
    rescue Exception; end
  end
  def self.bgm_stop(*a)
    begin
      if Audio.respond_to?(:web_bgm_stop); web_bgm_stop; else (__web_bgm_stop rescue nil); end
    rescue Exception; end
  end
  def self.bgm_fade(*a)
    begin
      if Audio.respond_to?(:web_bgm_fade); web_bgm_fade(a[0].to_i); else (__web_bgm_fade(a[0].to_i) rescue nil); end
    rescue Exception; end
  end
end

#===========================================================
# WEB PORT SHIM — Marshal support for Time (in-game saving), in CRuby's format.
# mruby-marshal cannot dump mruby-time's Time (MRB_TT_DATA) by itself; saves carry
# live Time objects ($player.last_time_saved, @startTime, @pokerusTime...).
# The dump is byte-compatible with CRuby's Time#_dump (time_mdump), so saves move
# between mkxp-web and mkxp-z (PC / Switch):
#   8 bytes, two little-endian 32-bit words, the broken-down UTC time:
#     p = 1<<31 | utc?<<30 | (year-1900)<<14 | (mon-1)<<10 | mday<<5 | hour
#     s = min<<26 | sec<<20 | usec
#   plus the ivars of the dumped string: :offset (UTC offset in seconds, local times),
#   :zone, and :nano_num/:nano_den/:submicro (sub-microsecond part).
# mruby strings hold no ivars, so the vendored mruby-marshal (extra/mruby-marshal)
# takes them from #_dump_ivars and hands them to Time._load_ivars.
# Until 2026-09 the web wrote the epoch as a decimal string ("1790000000"); that is
# still read. mruby's Time has no fixed-offset zone: a loaded time is the same instant
# in the browser's local zone, and re-dumps the offset/zone/nanoseconds it came with.
#===========================================================
class Time
  def self.__web_days_from_civil(y, m, d)
    y -= 1 if m <= 2
    era = (y >= 0 ? y : y - 399) / 400
    yoe = y - era * 400
    doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
    doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    era * 146097 + doe - 719468
  end

  # Seconds east of UTC (mruby-time has no utc_offset).
  def utc_offset
    return 0 if utc?
    Time.__web_days_from_civil(year, mon, day) * 86400 + hour * 3600 + min * 60 + sec - to_i
  end unless method_defined?(:utc_offset)
  alias_method :gmt_offset, :utc_offset unless method_defined?(:gmt_offset)
  alias_method :gmtoff, :utc_offset unless method_defined?(:gmtoff)

  def _dump(*)
    u = getutc
    p = (1 << 31) | ((utc? ? 1 : 0) << 30) | ((u.year - 1900) << 14) |
        ((u.mon - 1) << 10) | (u.day << 5) | u.hour
    s = (u.min << 26) | (u.sec << 20) | (usec & 0xfffff)
    [p, s].pack("VV")
  end

  def _dump_ivars
    iv = @__marshal_ivars
    return iv if iv.is_a?(Hash) && !iv.empty? && (iv.has_key?(:offset) != utc?)
    utc? ? { :zone => "UTC" } : { :offset => utc_offset }
  end

  def self._load(data)
    _load_ivars(data, nil)
  end

  def self._load_ivars(data, ivars)
    data = data.to_s
    digits = true
    data.bytesize.times { |i| b = data.getbyte(i); digits = false unless b >= 48 && b <= 57 }
    if data.bytesize != 8 || digits
      return Time.at(data.to_i) # mkxp-web before 2026-09: decimal epoch seconds
    end
    p, s = data.unpack("VV")
    if (p & (1 << 31)) == 0
      t = Time.at(p, s)         # CRuby's pre-1.9 layout: seconds, microseconds
    else
      year = ((p >> 14) & 0xffff) + 1900
      year = ivars[:year] if ivars && ivars[:year].is_a?(Integer)
      mon  = ((p >> 10) & 0xf) + 1
      mday = (p >> 5) & 0x1f
      hour = p & 0x1f
      min  = (s >> 26) & 0x3f
      sec  = (s >> 20) & 0x3f
      usec = s & 0xfffff
      epoch = __web_days_from_civil(year, mon, mday) * 86400 + hour * 3600 + min * 60 + sec
      t = Time.at(epoch, usec)
      t = t.getutc if ((p >> 30) & 1) == 1
    end
    t.instance_variable_set(:@__marshal_ivars, ivars) if ivars && !ivars.empty?
    t
  end
end

#===========================================================
# WEB PORT SHIM — minimal Errno (this mruby build lacks mruby-errno). Essentials
# has many `rescue Errno::ENOENT`/EINVAL/EACCES/SystemCallError clauses (file I/O,
# save, dir checks) that would otherwise raise NameError: uninitialized constant.
#===========================================================
class SystemCallError < StandardError; end unless Object.const_defined?(:SystemCallError)
module Errno
  %w[ENOENT EINVAL EACCES EEXIST ENOTDIR EISDIR ENOSPC EAGAIN EBADF EPERM].each do |n|
    const_set(n, Class.new(SystemCallError)) unless const_defined?(n)
  end
end

#===========================================================
# WEB PORT (VX): forgiving dispose on nil. RGSS2 Window#contents / many game
# objects default to a disposable empty Bitmap; mkxp's WindowVX etc. default them
# to nil, so the stock idioms `self.contents.dispose` (Window_Base#create_contents,
# #dispose) and `sprite.bitmap.dispose` hit nil. RGSS scripts assume dispose/
# disposed? are always safe to call, so make nil answer them (no-op / already-gone).
#===========================================================
class NilClass
  def dispose; end
  def disposed?; true; end
  # WEB PORT (mruby compat): mruby's NilClass (deps/mruby/src/object.c:289-297) defines only
  # & ^ | nil? to_s inspect. It OMITS the standard nil coercions to_i / to_f / to_a that CRuby and
  # RGSS2's Ruby 1.8 both provide (nil.to_i => 0, nil.to_f => 0.0, nil.to_a => []). VX games
  # lean on them pervasively — many `.to_i` / `.to_f` sites, often on values that can be nil
  # (e.g. the sideview action machine's `@wait = active.to_i` when `@action.shift` yields nil).
  # Without these, such a nil raises NoMethodError and
  # freezes the frame. Restoring the standard coercions is safe: no code expects nil.to_i to raise.
  def to_i; 0; end unless method_defined?(:to_i)
  def to_f; 0.0; end unless method_defined?(:to_f)
  def to_a; []; end unless method_defined?(:to_a)
  # WEB PORT (defensive shim, NOT a Ruby 1.8 method): several battle/menu scripts call
  # `.include?` on an attribute that is meant to be an array but can arrive nil — Marshal.load
  # rebuilds RPG data objects without running initialize (so any array field the editor didn't
  # serialize stays nil), and a few custom scripts (a choice UI: @choice_hide/@can_not_select,
  # $game_party.group[var]) read arrays before they are set. On CRuby those happened to be
  # populated; here a nil receiver raises NoMethodError and freezes the frame. Treating nil as an
  # empty collection (contains nothing) is the correct, side-effect-free default at every site.
  def include?(*); false; end unless method_defined?(:include?)
end

# WEB PORT (mruby compat): Ruby 1.8 / RGSS2 gave every object a deprecated #id, an alias of
# object_id. Ruby 1.9 removed it and mruby ships only object_id / __id__. The sideview battle
# system (Spriteset_Battle#update_actors) compares @actor_sprites[i].battler.id
# against $game_party.members[i].id for every actor slot up to the sideview member cap (4). When the
# party is smaller than 4 (e.g. early on), both sides are nil and the script
# relies on nil.id being a harmless constant integer (4 in Ruby 1.8) so the "did the party
# change?" check is simply false. On mruby nil.id is NoMethodError, which freezes the battle on
# its first frame (during the "enemy appears" intro). Restore the 1.8 alias. Classes with their
# own #id (Game_Actor, RPG::BaseItem, ...) override it; this only supplies the Object
# fallback for nil / arrays / plain objects, and no code calls respond_to?(:id), so making #id
# universally answerable is safe.
class Object
  def id; object_id; end unless method_defined?(:id)
end

# WEB PORT: RGSS2/VX Bitmap methods not exposed by this fork's XP-era Bitmap binding.
# clear_rect(x,y,w,h) or clear_rect(rect) blanks a region — implement via fill_rect
# with a transparent colour.
# WEB PORT (VX): the engine's TilemapVX "bitmaps" proxy is wrapped via a data type
# named "TilemapVXBitmapArray" (wrapObject does mrb_class_get on that name), but the
# binding defines the class as "TilemapBitmaps". Alias the expected constant to the
# real class so Tilemap.new can build its bitmaps proxy (with []/[]=) without a
# recompile. Marshal/engine define TilemapBitmaps at binding-init, before scripts run.
# NB: mruby 2.1.2 does not support the `defined?` operator (it parses as a method
# call -> "undefined method 'defined?'"), so probe constants with const_defined?.
if Object.const_defined?(:TilemapBitmaps) && !Object.const_defined?(:TilemapVXBitmapArray)
  TilemapVXBitmapArray = TilemapBitmaps
end

# WEB PORT (VX): a VX game's Spriteset_Map feeds `@tilemap.passages = $game_map.passages`,
# but mkxp's TilemapVX renders from `flags`/`map_data`, not `passages`. Accept and store
# the value so the assignment doesn't raise; tile passability itself stays game-side on
# $game_map. Guarded so a real binding (if ever added) wins.
if Object.const_defined?(:Tilemap)
  class Tilemap
    def passages=(v); @passages = v; end unless method_defined?(:passages=)
    def passages; @passages; end unless method_defined?(:passages)
  end
end

# WEB PORT: mruby-marshal streams to/from an IO ONE BYTE AT A TIME, which froze the game
# on BOTH sides of a savefile:
#   * dump(obj, io): io_out::byte -> mrb_funcall(io,"write",<1 byte>). $game_map (~680 KB)
#     is hundreds of thousands of write() funcalls+syscalls -> save hung (and hung outright
#     when the slot file didn't exist yet -- the empty-slot freeze).
#   * load(io): io_in::byte -> mrb_funcall(io,"getc") per byte, and mruby-io's buffered getc
#     re-slices its read buffer on every call (O(bufsize) per byte) -> loading a save AND
#     drawing the save-slot previews (Window_SaveFile reads 8 streams in initialize) hung
#     the load screen / the save-select screen when saves already existed.
# The in-memory String forms (string_out/string_in) do zero funcalls and are fast. So:
#   * dump writes a 4-byte length prefix + the whole marshal buffer in one io.write.
#   * load bulk-reads exactly that stream (one io.read) and loads it from the String.
# Standard un-prefixed streams (old web saves, and every save written by mkxp-z on PC /
# Switch) are detected (their first 4 bytes are the marshal version 04 08, i.e. an
# implausibly huge "length"): the rest of the file is read in one go, one object is loaded
# from memory (Marshal.__load_partial) and the stream is put right after it. Only an IO
# without seek falls back to the native byte reader (correct, just slow).
# NOTE: the prefix makes web saves unreadable by a stock Marshal.load (mkxp-z); anything
# that moves saves between engines must strip it (4-byte big-endian length) / add it back.
if Object.const_defined?(:Marshal) && Marshal.respond_to?(:dump) && !Marshal.respond_to?(:__mkxp_str_dump)
  module Marshal
    class << self
      alias_method :__mkxp_str_dump, :dump
      alias_method :__mkxp_str_load, :load
      LP_MAX = 1 << 26   # 64 MB: above any real per-object stream, below 0x04080000 (~67 MB)

      def dump(obj, io = nil, limit = nil)
        return __mkxp_str_dump(obj)      if io.nil?          # Marshal.dump(obj)
        return __mkxp_str_dump(obj, io)  if io.is_a?(Integer) # Marshal.dump(obj, limit)
        s = __mkxp_str_dump(obj)                              # Marshal.dump(obj, io[, limit])
        io.write([s.bytesize].pack("N"))
        io.write(s)
        io
      end

      def load(src)
        return __mkxp_str_load(src) if src.is_a?(String)      # deep-copy path, unchanged
        h = (src.read(4) rescue nil)
        return __mkxp_str_load(src) unless h.is_a?(String) && h.bytesize == 4
        n = h.unpack("N").first
        return __mkxp_str_load(src.read(n)) if n && n >= 0 && n <= LP_MAX
        # Standard (un-prefixed) stream, e.g. a save written by mkxp-z / RPG Maker:
        # load it from memory and put the stream right after the object, so several
        # dumps in one file still load one by one.
        if Marshal.respond_to?(:__load_partial) && src.respond_to?(:seek) && src.respond_to?(:pos)
          start = src.pos - 4
          obj, used = __load_partial(h + (src.read || ""))
          src.seek(start + used)
          return obj
        end
        (src.ungetc(h) rescue nil)                            # legacy stream: restore header
        __mkxp_str_load(src)
      end
    end
  end
end

# WEB PORT: mruby's 'default' gembox provides no Kernel#exit, yet the game calls exit
# for Quit Game (Scene_Title) and on fatal guards (interpreter depth limit, missing
# start map). A browser can't terminate the process, so raise a dedicated error that
# unwinds cleanly to Main (117), which ends the scene loop instead of crashing with
# "undefined method 'exit'".
class MkxpExit < Exception; end unless Object.const_defined?(:MkxpExit)
module Kernel
  def exit(*);  raise MkxpExit; end
  def exit!(*); raise MkxpExit; end
end

# WEB PORT: the game freezes (silent, no error) in the scene that follows a large Marshal
# operation (save dump or load restore of ~680 KB $game_map). mruby's *generational* GC does
# frequent minor collections keyed on an old->young write barrier; the marshal's huge
# allocation burst appears to break that invariant, so a later collection loops. Switching to
# plain (non-generational) incremental mark-sweep avoids it. Slightly more full-GC work, but
# the game state is small enough that it's imperceptible.
(GC.generational_mode = false) rescue nil

# WEB PORT (mruby compat): RGSS2 targets Ruby 1.8, where Hash#index(value) returns the key for a
# given value. Ruby 1.9 renamed it to Hash#key and 2.0 removed Hash#index entirely; mruby ships
# only Hash#key. A script calls Hash#index on a hash
# to map a value back to its key, so on mruby it raises
# NoMethodError and freezes the instant that lookup runs. Restore the 1.8
# alias. (Array#index exists in mruby, so array callers are unaffected.)
class Hash
  alias_method :index, :key unless method_defined?(:index)
end

class Bitmap
  unless method_defined?(:clear_rect)
    def clear_rect(x, y = nil, width = nil, height = nil)
      if y.nil?
        r = x; x = r.x; y = r.y; width = r.width; height = r.height
      end
      fill_rect(x, y, width, height, Color.new(0, 0, 0, 0))
    end
  end

  # VX Bitmap effects that mkxp's RGSS1-era binding doesn't expose. blur/radial_blur
  # are cosmetic (menu backgrounds are the snapshot); a no-op keeps them sharp but
  # functional. gradient_fill_rect approximates the gradient with interpolated
  # fill_rect strips (used for HP/MP gauges). Each is guarded so a real binding wins.
  def blur; end unless method_defined?(:blur)
  def radial_blur(angle, division); end unless method_defined?(:radial_blur)
  def hue_change(hue); end unless method_defined?(:hue_change)
  unless method_defined?(:gradient_fill_rect)
    def gradient_fill_rect(*a)
      if a[0].is_a?(Rect)
        r = a[0]; x = r.x; y = r.y; w = r.width; h = r.height; c1 = a[1]; c2 = a[2]; vert = a[3]
      else
        x, y, w, h, c1, c2, vert = a
      end
      steps = (vert ? h : w).to_i
      steps = 1 if steps < 1
      lerp = lambda { |i| steps <= 1 ? 0.0 : i.to_f / (steps - 1) }
      (0...steps).each do |i|
        t = lerp.call(i)
        col = Color.new(c1.red   + (c2.red   - c1.red)   * t,
                        c1.green + (c2.green - c1.green) * t,
                        c1.blue  + (c2.blue  - c1.blue)  * t,
                        c1.alpha + (c2.alpha - c1.alpha) * t)
        vert ? fill_rect(x, y + i, w, 1, col) : fill_rect(x + i, y, 1, h, col)
      end
    end
  end

  # RGSS Bitmap#draw_text coerces its text arg (games pass Integers and even nil,
  # e.g. a Window_Command built with [nil,nil,nil] when the menu is drawn with
  # sprites instead). mkxp's binding wants a String and raises "nil cannot be
  # converted to String" — wrap it to coerce, matching RGSS.
  alias __mkxp_draw_text draw_text
  def draw_text(*a)
    # NB: mkxp's draw_text picks the (rect,str) vs (x,y,w,h,str) form from the arg
    # COUNT, so we must forward with explicit args — a splat (`*a`) makes argc -1 and
    # sends it down the (x,y,w,h) path ("can't convert Rect to Integer").
    case a.size
    when 2 then __mkxp_draw_text(a[0], a[1].to_s)
    when 3 then __mkxp_draw_text(a[0], a[1].to_s, a[2])
    when 5 then __mkxp_draw_text(a[0], a[1], a[2], a[3], a[4].to_s)
    when 6 then __mkxp_draw_text(a[0], a[1], a[2], a[3], a[4].to_s, a[5])
    else        __mkxp_draw_text(*a)
    end
  end
end

# WEB PORT: Module reflection predicates RGSS plugins use at load-time (e.g.
# `alias x y unless private_method_defined?(:x)`) that mruby's metaprog lacks.
class Module
  unless method_defined?(:private_method_defined?)
    def private_method_defined?(n); (private_instance_methods(true) rescue []).include?(n.to_sym); end
  end
  unless method_defined?(:protected_method_defined?)
    def protected_method_defined?(n); (protected_instance_methods(true) rescue []).include?(n.to_sym); end
  end
  unless method_defined?(:public_method_defined?)
    def public_method_defined?(n); (public_instance_methods(true) rescue instance_methods(true) rescue []).include?(n.to_sym); end
  end
end

#===========================================================
# WEB PORT (VX): RGSS2 nested RPG data classes that Data/System.rvdata and
# Data/Map*.rvdata reference via Marshal but that the (XP-shaped) shim above did
# not declare. mruby-marshal only needs the class to EXIST — it restores the
# instance variables regardless of the body — so empty classes are enough for
# data the game never calls methods on (e.g. vehicles). Accessors can be added
# later if a script actually reads one of these.
#===========================================================
module RPG
  class System
    unless const_defined?(:Vehicle, false)
      class Vehicle
        attr_accessor :character_name, :character_index, :bgm,
                      :start_map_id, :start_x, :start_y
        def initialize; @character_name = ""; @character_index = 0; @start_map_id = 0; @start_x = 0; @start_y = 0; end
      end
    end
    # RGSS2 Terms holds ~30 UI label strings (skill, item, equip, hp, atk, ...).
    # Rather than enumerate them all, expose whatever Marshal restored: a reader
    # returns its @ivar (or "" if unset), a writer sets it. Safe because every
    # Terms field is a display string.
    unless const_defined?(:Terms, false)
      class Terms
        def method_missing(name, *args)
          s = name.to_s
          if s.end_with?('=')
            instance_variable_set("@#{s.chomp('=')}", args[0])
          else
            iv = "@#{s}"
            instance_variable_defined?(iv) ? instance_variable_get(iv) : ""
          end
        end
        def respond_to_missing?(*); true; end
      end
    end
    # RGSS2 RPG::System fields absent from the XP-shaped shim above. Marshal has
    # already populated the @ivars from System.rvdata; these just expose them.
    # (Re-declaring an accessor the shim already had is a harmless no-op.)
    attr_accessor :game_title, :version_id, :party_members, :elements,
                  :switches, :variables, :passages,
                  :boat, :ship, :airship,
                  :title_bgm, :battle_bgm, :battle_end_me, :gameover_me,
                  :sounds, :test_battlers, :test_troop_id,
                  :start_map_id, :start_x, :start_y,
                  :terms, :battler_name, :battler_hue, :edit_map_id
  end
  class Map
    class Encounter; end unless const_defined?(:Encounter, false)
  end
  # RGSS2: every database record carries a "note" box (the editor Note field), and
  # param add-on scripts parse it heavily (<...> tags). The XP-shaped shim classes lack
  # it, so mix a note reader/writer into each noted class. Marshal fills @note from
  # the real data; we default to "" when the record has no note.
  module Noted
    def note; @note ||= ""; end
    def note=(v); @note = v; end
  end
  class BaseItem; include Noted; end   # -> Skill/Item/Weapon/Armor/UsableItem
  class Actor;    include Noted; end
  class Class;    include Noted; end
  class Enemy;    include Noted; end
  class State;    include Noted; end
  # RGSS2 audio-file subclasses (map BGM/BGS, system SE/ME, etc.). Subclass
  # AudioFile so they inherit name/volume/pitch accessors used by the game.
  AudioFile = Class.new unless const_defined?(:AudioFile, false)
  # RGSS2 audio-file play/stop/fade. $data_system.title_bgm etc. are RPG::BGM after
  # Marshal, and the game calls .play on them; give the subclasses the standard
  # Audio.* routing (the base is a silent no-op so a bare AudioFile never crashes).
  class AudioFile
    def play(*); end
  end
  # RGSS2 also exposes RPG::BGM.last / RPG::BGS.last (the currently-playing track),
  # used by save/restore and the BGM-resume plugin. mkxp doesn't provide these (the
  # shim owns these classes), so track the last-played instance per class.
  unless const_defined?(:BGM, false)
    class BGM < AudioFile
      def play(*)
        n = @name.to_s
        n.empty? ? Audio.bgm_stop : Audio.bgm_play("Audio/BGM/" + n, @volume || 100, @pitch || 100)
        BGM.instance_variable_set(:@last, self)
      end
      def self.last; @last || new; end
      def self.stop; @last = nil; Audio.bgm_stop; end
      def self.fade(t); Audio.bgm_fade(t); end
    end
  end
  unless const_defined?(:BGS, false)
    class BGS < AudioFile
      def play(*)
        n = @name.to_s
        n.empty? ? Audio.bgs_stop : Audio.bgs_play("Audio/BGS/" + n, @volume || 100, @pitch || 100)
        BGS.instance_variable_set(:@last, self)
      end
      def self.last; @last || new; end
      def self.stop; @last = nil; Audio.bgs_stop; end
      def self.fade(t); Audio.bgs_fade(t); end
    end
  end
  unless const_defined?(:ME, false)
    class ME < AudioFile
      def play(*)
        n = @name.to_s
        n.empty? ? Audio.me_stop : Audio.me_play("Audio/ME/" + n, @volume || 100, @pitch || 100)
        ME.instance_variable_set(:@last, self)
      end
      def self.last; @last || new; end
      def self.stop; @last = nil; Audio.me_stop; end
      def self.fade(t); Audio.me_fade(t); end
    end
  end
  unless const_defined?(:SE, false)
    class SE < AudioFile
      def play(*); n = @name.to_s; Audio.se_play("Audio/SE/" + n, @volume || 100, @pitch || 100) unless n.empty?; end
      def self.stop; Audio.se_stop; end
    end
  end
end

