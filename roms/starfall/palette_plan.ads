------------------------------------------------------------------------------
--  STARFALL : who owns which part of the 256-colour palette.
--
--    bank  1  stars          bank  6  exhaust sparks
--    bank  2  mountains      bank  7  meteors
--    bank  3  reflections    bank  8  title text (colour-cycled)
--    bank  4  sun            bank  9  HUD text
--    bank  5  ship           bank 10  HUD accent
--    176 .. 215  sky gradient   (picked per scanline by the backdrop table)
--    216 .. 239  sea gradient
--    bank 15     default text
------------------------------------------------------------------------------

with Nova.Hardware; use Nova.Hardware;

package Palette_Plan is
   pragma Preelaborate;

   Star_Bank       : constant Palette_Bank := 1;
   Mountain_Bank   : constant Palette_Bank := 2;
   Reflection_Bank : constant Palette_Bank := 3;
   Sun_Bank        : constant Palette_Bank := 4;
   Ship_Bank       : constant Palette_Bank := 5;
   Spark_Bank      : constant Palette_Bank := 6;
   Meteor_Bank     : constant Palette_Bank := 7;
   Title_Bank      : constant Palette_Bank := 8;
   Hud_Bank        : constant Palette_Bank := 9;
   Accent_Bank     : constant Palette_Bank := 10;

   Sky_First  : constant Color_Index := 176;
   Sky_Shades : constant := 40;
   Sea_First  : constant Color_Index := 216;
   Sea_Shades : constant := 24;

end Palette_Plan;
