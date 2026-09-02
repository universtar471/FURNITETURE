# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Core
      # SketchUp only defines Length#to_mm, not Numeric#to_mm. Length arithmetic
      # silently degrades to Float in several places (Length * Float, Length - Float),
      # so calling +to_mm+ directly on the result raises NoMethodError.
      # Every millimetre conversion in this extension goes through here instead.
      module Units
        INCH_TO_MM = 25.4
        MM_TO_INCH = 1.0 / 25.4

        module_function

        # Any numeric or Length, interpreted as internal inches -> millimetres.
        def to_mm(value)
          return 0.0 if value.nil?
          value.to_f * INCH_TO_MM
        end

        # Millimetres -> internal inches.
        def mm(value)
          return 0.0 if value.nil?
          value.to_f * MM_TO_INCH
        end

        # Rounds a millimetre value the way a fabricator reads it.
        def round_mm(value, digits = 1)
          to_mm(value).round(digits)
        end

        # True when two internal-inch values are equal within +tol_mm+.
        def near?(a, b, tol_mm = 0.5)
          (a.to_f - b.to_f).abs <= mm(tol_mm)
        end

        # Clamps a numeric into [min, max].
        def clamp(value, min, max)
          v = value.to_f
          return min.to_f if v < min.to_f
          return max.to_f if v > max.to_f
          v
        end
      end
    end
  end
end
