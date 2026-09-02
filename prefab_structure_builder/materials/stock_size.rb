module KTSHung
  module PrefabStructureBuilder
    module Materials
      module StockSize
        module_function

        # Splits a required rectangle into stock-limited rectangular pieces.
        # Returns millimetre dimensions only; geometry creation is handled elsewhere.
        def split_rectangle(required_w, required_l, stock_w, stock_l, allow_rotate=false)
          rw=required_w.to_f; rl=required_l.to_f; sw=stock_w.to_f; sl=stock_l.to_f
          raise 'Stock width/length must be > 0.' if sw <= 0 || sl <= 0
          normal = grid_plan(rw, rl, sw, sl, false)
          return normal unless allow_rotate
          rotated = grid_plan(rw, rl, sl, sw, true)
          score(rotated) < score(normal) ? rotated : normal
        end

        def grid_plan(rw, rl, sw, sl, rotated)
          nx=[(rl/sl).ceil,1].max; ny=[(rw/sw).ceil,1].max
          pieces=[]
          nx.times do |ix|
            ny.times do |iy|
              l=[sl, rl-ix*sl].min
              w=[sw, rw-iy*sw].min
              next if l <= 0 || w <= 0
              pieces << {
                x_mm: ix*sl, y_mm: iy*sw, width_mm:w, length_mm:l,
                stock_width_mm:sw, stock_length_mm:sl,
                rotated:rotated, status:(w < sw-0.01 || l < sl-0.01) ? 'CUT' : 'FULL'
              }
            end
          end
          pieces
        end

        # Lower is better. Piece count dominates; leftover area breaks ties.
        # This used to return an Array, and Array does not implement #<, so
        # comparing two plans raised NoMethodError for every rotatable material
        # (which includes every Cemboard preset).
        def score(plan)
          return Float::INFINITY if plan.empty?
          stock_area = plan.sum { |p| p[:stock_width_mm] * p[:stock_length_mm] }
          used_area  = plan.sum { |p| p[:width_mm] * p[:length_mm] }
          waste = [stock_area - used_area, 0.0].max
          # 1 m2 of waste is worth far less than one extra sheet.
          plan.length * 1_000_000.0 + waste
        end

        def stats(plan)
          stock_area=plan.sum{|p| p[:stock_width_mm]*p[:stock_length_mm]}
          used_area=plan.sum{|p| p[:width_mm]*p[:length_mm]}
          waste=[stock_area-used_area,0.0].max
          {
            pieces:plan.length,
            full:plan.count{|p| p[:status]=='FULL'},
            cut:plan.count{|p| p[:status]=='CUT'},
            used_m2:(used_area/1_000_000.0).round(3),
            purchase_m2:(stock_area/1_000_000.0).round(3),
            waste_m2:(waste/1_000_000.0).round(3),
            waste_percent:(stock_area > 0 ? waste*100.0/stock_area : 0).round(1)
          }
        end

        def violation?(width_mm, length_mm, stock_width_mm, stock_length_mm, allow_rotate=false)
          fits = width_mm.to_f <= stock_width_mm.to_f + 0.01 && length_mm.to_f <= stock_length_mm.to_f + 0.01
          return false if fits
          return true unless allow_rotate
          !(width_mm.to_f <= stock_length_mm.to_f + 0.01 && length_mm.to_f <= stock_width_mm.to_f + 0.01)
        end
      end
    end
  end
end
