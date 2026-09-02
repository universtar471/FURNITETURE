# encoding: UTF-8
# Minimal stand-ins for the SketchUp Ruby API, enough to load and exercise the
# geometry-free parts of the extension outside SketchUp.
require 'json'

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      if x.is_a?(Array)
        @x, @y, @z = x[0].to_f, x[1].to_f, x[2].to_f
      else
        @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
    end
    def -(other); Vector3d.new(@x - other.x, @y - other.y, @z - other.z); end
    def distance(other); Math.sqrt((@x - other.x)**2 + (@y - other.y)**2 + (@z - other.z)**2); end
    def to_a; [@x, @y, @z]; end
  end

  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
    def length; Math.sqrt(@x**2 + @y**2 + @z**2); end
    def clone; Vector3d.new(@x, @y, @z); end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def normalize!; l = length; (@x /= l; @y /= l; @z /= l) if l > 0; self; end
    def cross(o); Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x); end
    def dot(o); @x * o.x + @y * o.y + @z * o.z; end
    def to_a; [@x, @y, @z]; end
  end

  class BoundingBox
    def initialize; @pts = []; end
    def add(p); @pts << p; self; end
    def min; Point3d.new(@pts.map(&:x).min || 0, @pts.map(&:y).min || 0, @pts.map(&:z).min || 0); end
    def max; Point3d.new(@pts.map(&:x).max || 0, @pts.map(&:y).max || 0, @pts.map(&:z).max || 0); end
    def width;  max.x - min.x; end
    def height; max.y - min.y; end
    def depth;  max.z - min.z; end
    def center; Point3d.new((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2); end
  end

  class Transformation
    def initialize(*); end
    def self.translation(*); new; end
    def self.rotation(*); new; end
    def self.axes(*); new; end
    def *(_other); self; end
    def to_a; Array.new(16, 0.0); end
  end
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)

class Numeric
  def mm; self * (1.0 / 25.4); end
  def degrees; self * Math::PI / 180.0; end
  # Deliberately NOT defining Numeric#to_mm: SketchUp does not define it either,
  # and the tests rely on that to catch conversions that bypass Core::Units.
end

module Sketchup
  class Color
    attr_reader :red, :green, :blue
    def initialize(r = 0, g = 0, b = 0); @red, @green, @blue = r, g, b; end
  end

  class Layer
    attr_accessor :name, :color, :visible
    def initialize(name); @name = name; @visible = true; end
    def visible?; @visible; end
  end

  class Layers
    def initialize; @layers = {}; end
    def [](name); @layers[name.to_s]; end
    def add(name); @layers[name.to_s] ||= Layer.new(name.to_s); end
    def length; @layers.length; end
  end

  class Entity
    attr_accessor :name
    def initialize; @attrs = {}; @name = ''; end
    def entityID; object_id; end
    def valid?; true; end
    def set_attribute(dict, key, value); (@attrs[dict] ||= {})[key.to_s] = value; end
    def get_attribute(dict, key, default = nil)
      d = @attrs[dict]
      d && d.key?(key.to_s) ? d[key.to_s] : default
    end
  end

  class Group < Entity; end
  class ComponentInstance < Entity; end
  class Face < Entity; end

  class Model < Entity
    attr_reader :layers, :materials
    def initialize; super; @layers = Layers.new; @materials = {}; end
    def path; ''; end
    def start_operation(*); true; end
    def commit_operation; true; end
    def abort_operation; true; end
  end

  @model = Model.new
  class << self
    def active_model; @model; end
    def version; '26.0.0'; end
  end
end

module UI
  def self.messagebox(text); $stderr.puts("[messagebox] #{text}"); text; end
  def self.start_timer(*); 0; end
end
