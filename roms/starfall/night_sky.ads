------------------------------------------------------------------------------
--  STARFALL : stars and falling stars
--
--  Forty twinkling stars drift slowly behind the mountains. Every so often a
--  meteor streaks across with a fading six-sprite trail and vanishes behind
--  the ridge, which works because its sprites carry the Behind_BG0 bit.
------------------------------------------------------------------------------

package Night_Sky is

   procedure Build;
   procedure Update (Frame : Natural);

   Meteors_Seen : Natural := 0;

end Night_Sky;
