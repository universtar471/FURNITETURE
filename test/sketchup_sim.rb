# encoding: UTF-8
#
# A fuller SketchUp Ruby API simulator than sketchup_stub.rb.
#
# Faithful enough to EXECUTE the generators: real 4x4 transformation maths,
# bounding boxes that follow their group's transform, entity collections,
# faces with normals and pushpull, layers, materials, selection, attribute
# dictionaries, and an operation stack that refuses to nest.
#
# What it CANNOT tell you: whether the resulting solids are watertight, whether
# geometry looks right on screen, whether undo behaves, or anything about the
# HtmlDialog bridge or the toolbar. Those need a real SketchUp.
require 'json'

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      if x.is_a?(Array)      then @x, @y, @z = x[0].to_f, x[1].to_f, (x[2] || 0).to_f
      elsif x.is_a?(Point3d) then @x, @y, @z = x.x, x.y, x.z
      else                        @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
    end
    def [](i); [@x, @y, @z][i]; end
    def -(o)
      o.is_a?(Vector3d) ? Point3d.new(@x - o.x, @y - o.y, @z - o.z)
                        : Vector3d.new(@x - o.x, @y - o.y, @z - o.z)
    end
    def +(v); Point3d.new(@x + v.x, @y + v.y, @z + v.z); end
    def offset(v, d = nil)
      u = v.clone
      if d
        u.normalize!
        Point3d.new(@x + u.x * d, @y + u.y * d, @z + u.z * d)
      else
        Point3d.new(@x + u.x, @y + u.y, @z + u.z)
      end
    end
    def distance(o); Math.sqrt((@x - o.x)**2 + (@y - o.y)**2 + (@z - o.z)**2); end
    def transform(tr); tr.xform_point(self); end
    def clone; Point3d.new(@x, @y, @z); end
    def to_a; [@x, @y, @z]; end
    def ==(o); o.is_a?(Point3d) && to_a == o.to_a; end
  end

  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      if x.is_a?(Array) then @x, @y, @z = x[0].to_f, x[1].to_f, (x[2] || 0).to_f
      else                   @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
    end
    def length; Math.sqrt(@x**2 + @y**2 + @z**2); end
    def clone; Vector3d.new(@x, @y, @z); end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def normalize!; l = length; (@x /= l; @y /= l; @z /= l) if l > 1e-12; self; end
    def normalize; clone.normalize!; end
    def cross(o); Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x); end
    def dot(o); @x * o.x + @y * o.y + @z * o.z; end
    def to_a; [@x, @y, @z]; end
  end

  class BoundingBox
    def initialize; @min = nil; @max = nil; end
    def add(o)
      case o
      when BoundingBox then (add(o.min); add(o.max)) unless o.empty?
      when Array       then o.each { |p| add(p) }
      else
        p = o.is_a?(Point3d) ? o : Point3d.new(o)
        if @min.nil?
          @min = p.clone; @max = p.clone
        else
          @min = Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min)
          @max = Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max)
        end
      end
      self
    end
    def empty?; @min.nil?; end
    def min; @min || Point3d.new(0, 0, 0); end
    def max; @max || Point3d.new(0, 0, 0); end
    def width;  max.x - min.x; end
    def height; max.y - min.y; end
    def depth;  max.z - min.z; end
    def center; Point3d.new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, (min.z + max.z) / 2.0); end
    def corner(i)
      # SketchUp's corner order.
      xs = [min.x, max.x]; ys = [min.y, max.y]; zs = [min.z, max.z]
      Point3d.new(xs[i & 1], ys[(i >> 1) & 1], zs[(i >> 2) & 1])
    end
  end

  # Column-major 4x4, matching Transformation#to_a.
  class Transformation
    attr_reader :m
    def initialize(arg = nil)
      @m = if arg.is_a?(Array) && arg.length == 16 then arg.map(&:to_f)
           elsif arg.is_a?(Transformation)         then arg.m.dup
           else [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1].map(&:to_f)
           end
    end

    def self.translation(v)
      x, y, z = v.is_a?(Array) ? [v[0], v[1], v[2] || 0] : [v.x, v.y, v.z]
      new([1,0,0,0, 0,1,0,0, 0,0,1,0, x.to_f, y.to_f, z.to_f, 1])
    end

    def self.axes(origin, xa, ya, za)
      o = origin.is_a?(Point3d) ? origin : Point3d.new(origin)
      new([xa.x, xa.y, xa.z, 0, ya.x, ya.y, ya.z, 0, za.x, za.y, za.z, 0, o.x, o.y, o.z, 1])
    end

    def self.rotation(point, vector, angle)
      o = point.is_a?(Point3d) ? point : Point3d.new(point)
      a = vector.clone.normalize!
      c = Math.cos(angle); s = Math.sin(angle); t = 1 - c
      r = [
        t*a.x*a.x + c,      t*a.x*a.y + s*a.z,  t*a.x*a.z - s*a.y, 0,
        t*a.x*a.y - s*a.z,  t*a.y*a.y + c,      t*a.y*a.z + s*a.x, 0,
        t*a.x*a.z + s*a.y,  t*a.y*a.z - s*a.x,  t*a.z*a.z + c,     0,
        0, 0, 0, 1
      ]
      rot = new(r)
      translation(Vector3d.new(o.x, o.y, o.z)) * rot * translation(Vector3d.new(-o.x, -o.y, -o.z))
    end

    def xform_point(p)
      Point3d.new(
        @m[0]*p.x + @m[4]*p.y + @m[8]*p.z  + @m[12],
        @m[1]*p.x + @m[5]*p.y + @m[9]*p.z  + @m[13],
        @m[2]*p.x + @m[6]*p.y + @m[10]*p.z + @m[14]
      )
    end

    def *(o)
      raise TypeError, "cannot multiply Transformation by #{o.class}" unless o.is_a?(Transformation)
      r = Array.new(16, 0.0)
      4.times do |c|
        4.times do |i|
          r[c*4+i] = (0..3).sum { |k| @m[k*4+i] * o.m[c*4+k] }
        end
      end
      Transformation.new(r)
    end

    def to_a; @m.dup; end
  end
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)

class Numeric
  def mm; self * (1.0 / 25.4); end
  def degrees; self * Math::PI / 180.0; end
  # No Numeric#to_mm, exactly as in SketchUp.
end

module Sketchup
  class Color
    attr_reader :red, :green, :blue
    def initialize(r = 0, g = 0, b = 0); @red, @green, @blue = r, g, b; end
  end

  class Material
    attr_accessor :name, :color
    def initialize(name); @name = name; end
  end

  class Materials
    def initialize; @by_name = {}; end
    def [](n); @by_name[n.to_s]; end
    def add(n); @by_name[n.to_s] ||= Material.new(n.to_s); end
    def length; @by_name.length; end
    def each(&b); @by_name.values.each(&b); end
  end

  class Layer
    attr_accessor :name, :color
    def initialize(name); @name = name; @visible = true; end
    def visible?; @visible; end
  end

  class Layers
    def initialize; @by_name = {}; end
    def [](n); @by_name[n.to_s]; end
    def add(n); @by_name[n.to_s] ||= Layer.new(n.to_s); end
    def length; @by_name.length; end
    def each(&b); @by_name.values.each(&b); end
  end

  @next_id = 1
  def self.next_id; @next_id += 1; end

  class Entity
    attr_accessor :name, :layer, :material, :parent
    def initialize
      @attrs = {}
      @name = ''
      @id = Sketchup.next_id
      @deleted = false
    end
    def entityID; @id; end
    def persistent_id; @id; end
    def valid?; !@deleted; end
    def erase!
      raise 'entity already erased' if @deleted
      @deleted = true
      @parent.remove(self) if @parent
      nil
    end
    def set_attribute(dict, key, value); (@attrs[dict] ||= {})[key.to_s] = value; end
    def get_attribute(dict, key, default = nil)
      d = @attrs[dict]
      d && d.key?(key.to_s) ? d[key.to_s] : default
    end
    def attribute_dictionaries; @attrs; end
  end

  class Edge < Entity
    attr_reader :start, :end
    def initialize(a, b); super(); @start = Vertex.new(a); @end = Vertex.new(b); end
    def bounds; bb = Geom::BoundingBox.new; bb.add(@start.position); bb.add(@end.position); bb; end
  end

  class Vertex
    attr_reader :position
    def initialize(p); @position = p; end
  end

  class Loop
    def initialize(pts); @pts = pts; end
    def vertices; @pts.map { |p| Vertex.new(p) }; end
    def edges
      @pts.each_with_index.map { |p, i| Edge.new(p, @pts[(i + 1) % @pts.length]) }
    end
  end

  class Face < Entity
    attr_reader :points, :normal
    attr_accessor :back_material
    def initialize(points)
      super()
      @points = points.map { |p| p.is_a?(Geom::Point3d) ? p : Geom::Point3d.new(p) }
      @normal = newell(@points)
      @extruded = []
    end

    def newell(pts)
      n = Geom::Vector3d.new(0, 0, 0)
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
      end
      n.length > 1e-12 ? n.normalize! : Geom::Vector3d.new(0, 0, 1)
    end

    def outer_loop; Loop.new(@points); end

    def pushpull(distance)
      d = distance.to_f
      raise ArgumentError, 'pushpull distance must not be zero' if d.abs < 1e-12
      @extruded = @points.map { |p| p.offset(@normal, d) }
      self
    end

    def bounds
      bb = Geom::BoundingBox.new
      (@points + @extruded).each { |p| bb.add(p) }
      bb
    end
  end

  class Entities
    include Enumerable
    def initialize(owner = nil); @list = []; @owner = owner; end
    def each(&b); @list.dup.each(&b); end
    def length; @list.length; end
    def size; @list.length; end
    def [](i); @list[i]; end
    def to_a; @list.dup; end
    def grep(klass); @list.select { |e| e.is_a?(klass) }; end
    def remove(e); @list.delete(e); end

    def add_group(*)
      g = Group.new
      g.parent = self
      @list << g
      g
    end

    def add_instance(definition, transformation)
      i = ComponentInstance.new(definition, transformation)
      i.parent = self
      @list << i
      i
    end

    def add_face(*args)
      pts = if args.length == 1 && args.first.is_a?(Array)
              first = args.first.first
              if first.is_a?(Edge)
                args.first.map { |e| e.start.position }
              else
                args.first
              end
            else
              args
            end
      pts = pts.map { |p| p.is_a?(Geom::Point3d) ? p : Geom::Point3d.new(p) }
      return nil if pts.length < 3
      # Reject degenerate outlines the way SketchUp does.
      return nil if pts.each_cons(2).any? { |a, b| a.distance(b) < 1e-9 }
      f = Face.new(pts)
      f.parent = self
      @list << f
      f
    end

    def add_circle(center, normal, radius, segments = 24)
      c = center.is_a?(Geom::Point3d) ? center : Geom::Point3d.new(center)
      n = normal.clone.normalize!
      helper = (n.z.abs > 0.9) ? X_AXIS : Z_AXIS
      u = helper.cross(n); u.normalize!
      v = n.cross(u); v.normalize!
      pts = (0...segments).map do |i|
        a = 2 * Math::PI * i / segments
        Geom::Point3d.new(c.x + radius * (u.x * Math.cos(a) + v.x * Math.sin(a)),
                          c.y + radius * (u.y * Math.cos(a) + v.y * Math.sin(a)),
                          c.z + radius * (u.z * Math.cos(a) + v.z * Math.sin(a)))
      end
      pts.each_with_index.map do |p, i|
        e = Edge.new(p, pts[(i + 1) % pts.length])
        e.parent = self
        @list << e
        e
      end
    end

    def bounds
      bb = Geom::BoundingBox.new
      @list.each { |e| bb.add(e.bounds) if e.respond_to?(:bounds) }
      bb
    end
  end

  class Group < Entity
    attr_reader :entities
    attr_accessor :transformation
    def initialize
      super
      @entities = Entities.new(self)
      @transformation = Geom::Transformation.new
    end
    def transform!(tr)
      @transformation = tr * @transformation
      self
    end
    def bounds
      local = @entities.bounds
      bb = Geom::BoundingBox.new
      return bb if local.empty?
      8.times { |i| bb.add(@transformation.xform_point(local.corner(i))) }
      bb
    end
    # Real SketchUp groups DO have a definition, named "Group#<n>".
    def definition
      @definition ||= begin
        d = ComponentDefinition.new("Group##{entityID}")
        d.instance_variable_set(:@entities, @entities)
        d
      end
    end
  end

  class ComponentDefinition < Entity
    attr_reader :entities
    def initialize(name = 'Definition')
      super()
      @entities = Entities.new(self)
      @name = name
    end
  end

  class ComponentInstance < Entity
    attr_accessor :transformation
    attr_reader :definition
    def initialize(definition = nil, transformation = nil)
      super()
      @definition = definition || ComponentDefinition.new
      @transformation = transformation || Geom::Transformation.new
    end
    def entities; @definition.entities; end
    def bounds
      local = @definition.entities.bounds
      bb = Geom::BoundingBox.new
      return bb if local.empty?
      8.times { |i| bb.add(@transformation.xform_point(local.corner(i))) }
      bb
    end
  end

  class Selection
    include Enumerable
    def initialize; @list = []; end
    def each(&b); @list.each(&b); end
    def add(*e); @list.concat(e.flatten); self; end
    def clear; @list = []; self; end
    def to_a; @list.dup; end
    def length; @list.length; end
    def empty?; @list.empty?; end
  end

  class View
    attr_reader :zoom_calls
    def initialize; @zoom_calls = []; end
    def zoom(e); @zoom_calls << e; true; end
  end

  class Model < Entity
    attr_reader :layers, :materials, :selection, :active_view, :operations
    def initialize
      super
      @entities = Entities.new(self)
      @layers = Layers.new
      @materials = Materials.new
      @selection = Selection.new
      @active_view = View.new
      @open_operation = nil
      @operations = []
    end
    def entities; @entities; end
    def path; ''; end

    # SketchUp silently commits an outer operation when a new one starts.
    # Here that is an error, so nested transactions are caught instead of
    # quietly splitting one user action into several undo steps.
    def start_operation(name, *)
      raise "nested start_operation: '#{name}' opened while '#{@open_operation}' is still open" if @open_operation
      @open_operation = name
      @operations << [:start, name]
      true
    end
    def commit_operation
      raise 'commit_operation without a matching start_operation' unless @open_operation
      @operations << [:commit, @open_operation]
      @open_operation = nil
      true
    end
    def abort_operation
      raise 'abort_operation without a matching start_operation' unless @open_operation
      @operations << [:abort, @open_operation]
      @open_operation = nil
      true
    end
    def operation_open?; !@open_operation.nil?; end

    def find_entity_by_id(id)
      found = nil
      walk = lambda do |ents|
        ents.each do |e|
          found ||= e if e.entityID == id
          walk.call(e.entities) if found.nil? && e.respond_to?(:entities) && e.entities
        end
      end
      walk.call(@entities)
      found
    end

    def reset!
      @entities = Entities.new(self)
      @layers = Layers.new
      @materials = Materials.new
      @selection = Selection.new
      @open_operation = nil
      @operations = []
      @attrs = {}
    end
  end

  @model = Model.new
  class << self
    def active_model; @model; end
    def version; '26.0.0'; end
  end
end

module UI
  class << self
    attr_accessor :messages
    def messagebox(text)
      (@messages ||= []) << text.to_s
      text
    end
    def start_timer(_seconds, _repeat = false, &block)
      (@timers ||= []) << block
      1
    end
    def timers; @timers ||= []; end
    def savepanel(*); nil; end
    def openpanel(*); nil; end
    def menu(*); MenuStub.new; end
    def reset!; @messages = []; @timers = []; end
  end

  class MenuStub
    def add_submenu(*); MenuStub.new; end
    def add_item(*); 1; end
    def add_separator; nil; end
  end

  class Command
    attr_accessor :small_icon, :large_icon, :tooltip, :status_bar_text
    def initialize(_name, &block); @block = block; end
    def call; @block.call; end
  end

  class Toolbar
    def initialize(_name); @items = []; end
    def add_item(c); @items << c; self; end
    def restore; self; end
    def show; self; end
    def size; @items.length; end
  end

  class HtmlDialog
    STYLE_DIALOG = 1
    attr_reader :scripts, :callbacks
    def initialize(*); @scripts = []; @callbacks = {}; @visible = false; end
    def set_file(*); true; end
    def add_action_callback(name, &b); @callbacks[name] = b; self; end
    def set_on_closed(&b); @on_closed = b; self; end
    def show; @visible = true; end
    def close; @visible = false; @on_closed&.call; end
    def visible?; @visible; end
    def execute_script(js); @scripts << js; true; end
    def invoke(name, *args)
      raise "no callback #{name}" unless @callbacks[name]
      @callbacks[name].call(self, *args)
    end
  end
end
