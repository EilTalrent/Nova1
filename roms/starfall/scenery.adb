with Interfaces;    use Interfaces;
with Nova.Hardware; use Nova.Hardware;
with Nova.Video;    use Nova.Video;
with Nova.Console;  use Nova.Console;
with Palette_Plan;  use Palette_Plan;

package body Scenery is

   Mountain_Rows : constant := 6;  --  tile rows above the horizon
   First_Mountain_Tile : constant Tile_Index := 256;
   Sun_Tile  : constant Tile_Index := 192;
   Sun_Id    : constant Sprite_Id := 15;
   Glint_Tile : constant Tile_Index := 138;
   subtype Glint_Id is Sprite_Id range 56 .. 61;

   Current_Darkness : Natural := 0;
   Current_Sun_Y    : Fixed   := 40.0;

   function Darkness return Natural is (Current_Darkness);
   function Sun_Y return Fixed is (Current_Sun_Y);

   ---------------------------------------------------------------------------
   --  Colour keys. Sky gradients are interpolated between four keys each.
   ---------------------------------------------------------------------------

   type Key_Colors is array (0 .. 3) of RGB;

   Dusk_Sky  : constant Key_Colors :=
     [Make_RGB (24, 16, 72), Make_RGB (92, 34, 128),
      Make_RGB (222, 78, 128), Make_RGB (255, 170, 92)];
   Night_Sky : constant Key_Colors :=
     [Make_RGB (4, 4, 20), Make_RGB (22, 12, 58),
      Make_RGB (84, 28, 92), Make_RGB (168, 62, 74)];
   Dusk_Sea  : constant Key_Colors :=
     [Make_RGB (150, 60, 110), Make_RGB (70, 30, 96),
      Make_RGB (28, 16, 64), Make_RGB (8, 6, 30)];
   Night_Sea : constant Key_Colors :=
     [Make_RGB (70, 26, 66), Make_RGB (30, 14, 50),
      Make_RGB (12, 8, 32), Make_RGB (2, 2, 12)];

   --  Position P in 0 .. 255 along a four-key gradient
   function Gradient (Keys : Key_Colors; P : Natural) return RGB is
      Seg : constant Natural := Natural'Min (2, P * 3 / 256);
      T   : constant Natural := (P * 3 - Seg * 256);
   begin
      return Mix (Keys (Seg), Keys (Seg + 1), Natural'Min (256, T));
   end Gradient;

   ---------------------------------------------------------------------------
   --  Mountains
   ---------------------------------------------------------------------------

   --  Ridge height in pixels above the horizon at world column X (0 .. 255).
   --  Three sine waves whose periods divide 256, so the map wraps seamlessly.
   function Ridge_Height (X : Natural) return Natural is
      H : constant Fixed :=
        22.0
        + Sin (Angle ((X * 2 + 40) mod 256)) * 11
        + Sin (Angle ((X * 5 + 100) mod 256)) * 7
        + Sin (Angle ((X * 13 + 7) mod 256)) * 3;
   begin
      return Natural'Max (1, Floor (H));
   end Ridge_Height;

   procedure Build_Mountains is
   begin
      for Col in Map_Column loop
         for R in 0 .. Mountain_Rows - 1 loop
            declare
               T : constant Tile_Index :=
                 First_Mountain_Tile + Tile_Index (Natural (Col) * Mountain_Rows + R);
            begin
               for PY in 0 .. 7 loop
                  for PX in 0 .. 7 loop
                     declare
                        WX     : constant Natural := Natural (Col) * 8 + PX;
                        Height : constant Natural := R * 8 + (7 - PY);
                        Top    : constant Natural := Ridge_Height (WX);
                        C      : Color_Index := 0;
                     begin
                        if Height < Top then
                           if Top - Height <= 2 then
                              C := 2;                      --  sunlit ridge
                           elsif (WX + Height * 3) mod 11 = 0
                             and then Top - Height > 5
                           then
                              C := 3;                      --  rock texture
                           else
                              C := 1;                      --  body
                           end if;
                        end if;
                        Tiles (T) (PY, PX) := C;
                     end;
                  end loop;
               end loop;

               --  The mountain itself, above the horizon...
               BG0_Map (Map_Row (15 - R), Col) :=
                 (Tile => T, Flip_H => False, Flip_V => False, Bank => Mountain_Bank);
               --  ...and its reflection: same tile, flipped, darker bank.
               BG0_Map (Map_Row (16 + R), Col) :=
                 (Tile => T, Flip_H => False, Flip_V => True, Bank => Reflection_Bank);
            end;
         end loop;
      end loop;
   end Build_Mountains;

   ---------------------------------------------------------------------------
   --  The sun: a 64x64 sprite made of 8x8 tiles, with synthwave stripes
   ---------------------------------------------------------------------------

   procedure Build_Sun is
   begin
      for Y in 0 .. 63 loop
         for X in 0 .. 63 loop
            declare
               DX : constant Integer := X * 2 - 63;   --  doubled, centred
               DY : constant Integer := Y * 2 - 63;
               Inside : constant Boolean := DX * DX + DY * DY <= 60 * 60;
               --  Gaps get wider toward the bottom of the disc
               Stripe : constant Boolean :=
                 Y >= 34 and then (Y mod 7) < (Y - 27) / 8;
               C : Color_Index := 0;
            begin
               if Inside and not Stripe then
                  C := Color_Index (1 + Y / 8);       --  8 bands, gold to rose
               end if;
               Tiles (Sun_Tile + Tile_Index ((Y / 8) * 8 + X / 8)) (Y mod 8, X mod 8) := C;
            end;
         end loop;
      end loop;

      --  A short horizontal sparkle for sunlight on the water
      for PX in 0 .. 7 loop
         for PY in 0 .. 7 loop
            Tiles (Glint_Tile) (PY, PX) :=
              (if PY = 4 and then PX in 1 .. 6 then (if PX in 3 .. 4 then 1 else 3)
               else 0);
         end loop;
      end loop;

      for I in Color_Index range 1 .. 8 loop
         Palette (Bank_Color (Sun_Bank, I)) :=
           Mix (Make_RGB (255, 236, 120), Make_RGB (255, 60, 140), Natural (I - 1) * 256 / 7);
      end loop;
   end Build_Sun;

   ---------------------------------------------------------------------------

   procedure Build is
   begin
      Clear (BG0);
      --  Sun, stars and meteors are windowed: they vanish at the horizon.
      Window_Top    := 0;
      Window_Bottom := Horizon;
      Build_Mountains;
      Build_Sun;

      --  The backdrop table: each scanline picks its own colour index.
      for Y in Scanline loop
         if Natural (Y) < Horizon then
            Line_Backdrop (Y) := Sky_First + Color_Index (Natural (Y) * Sky_Shades / Horizon);
         else
            Line_Backdrop (Y) :=
              Sea_First + Color_Index ((Natural (Y) - Horizon) * Sea_Shades
                                       / (Screen_Height - Horizon));
         end if;
         Line_Scroll (Y) := 0;
      end loop;

      Update (0);
   end Build;

   procedure Update (Frame : Natural) is
      Sun_Phase : constant Angle := Angle ((Frame / 8) mod 256);
   begin
      --  The sun sinks and rises on a slow 34-second cycle.
      Current_Sun_Y := 74.0 - Cos (Sun_Phase) * 36;
      Current_Darkness := Natural'Min (256, Natural'Max (0, (Floor (Current_Sun_Y) - 38) * 4));
      Place_Sprite (Sun_Id, 96, Floor (Current_Sun_Y), Sun_Tile,
                    Size => Size_64, Bank => Sun_Bank, Behind_BG0 => True,
                    Windowed => True);

      --  Glints on the water below the sun. Fewer as the light goes.
      if Frame mod 6 = 0 then
         for G in Glint_Id loop
            if Natural (G - Glint_Id'First) * 256 < (256 - Current_Darkness) * 6 then
               Place_Sprite (G, 128 + Random (-26, 18) * Random (2, 4) / 3,
                             Horizon + Random (0, 40), Glint_Tile,
                             Bank => Sun_Bank, Behind_BG0 => True);
            else
               OAM (G).Attr.Visible := False;
            end if;
         end loop;
      end if;

      --  Repaint the sky and sea for the current light.
      for I in 0 .. Sky_Shades - 1 loop
         Palette (Sky_First + Color_Index (I)) :=
           Mix (Gradient (Dusk_Sky, I * 256 / Sky_Shades),
                Gradient (Night_Sky, I * 256 / Sky_Shades), Current_Darkness);
      end loop;
      for I in 0 .. Sea_Shades - 1 loop
         Palette (Sea_First + Color_Index (I)) :=
           Mix (Gradient (Dusk_Sea, I * 256 / Sea_Shades),
                Gradient (Night_Sea, I * 256 / Sea_Shades), Current_Darkness);
      end loop;

      --  Mountains catch less light as the sun goes down.
      Palette (Bank_Color (Mountain_Bank, 1)) :=
        Mix (Make_RGB (70, 30, 92), Make_RGB (26, 12, 40), Current_Darkness);
      Palette (Bank_Color (Mountain_Bank, 2)) :=
        Mix (Make_RGB (255, 128, 120), Make_RGB (110, 50, 90), Current_Darkness);
      Palette (Bank_Color (Mountain_Bank, 3)) :=
        Mix (Make_RGB (96, 44, 112), Make_RGB (36, 18, 54), Current_Darkness);
      for C in Color_Index range 1 .. 3 loop
         Palette (Bank_Color (Reflection_Bank, C)) :=
           Mix (Palette (Bank_Color (Mountain_Bank, C)), Make_RGB (10, 8, 40), 150);
      end loop;

      --  Scroll the world, and ripple the water: deeper lines (closer to the
      --  viewer) swing wider and faster.
      BG0_Scroll_X := Integer_32 (Frame / 2);
      for Y in Scanline range Horizon .. Scanline'Last loop
         declare
            Depth : constant Natural := Natural (Y) - Horizon;
            Wave  : constant Fixed :=
              Sin (Angle ((Natural (Y) * 9 + Frame * 3) mod 256)) * (1 + Depth / 14);
         begin
            Line_Scroll (Y) := Integer_16 (Floor (Wave));
         end;
      end loop;
   end Update;

end Scenery;
