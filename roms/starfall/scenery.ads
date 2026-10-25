------------------------------------------------------------------------------
--  STARFALL : scenery
--
--  Everything behind the action: a sky gradient painted with the per-line
--  backdrop table, procedurally generated mountains on BG0, their reflection
--  (the same tiles, flipped vertically, in a darker palette bank) rippled by
--  the per-line scroll table, and a striped synthwave sun sinking behind the
--  ridge as the sky darkens.
------------------------------------------------------------------------------

with Nova.Math; use Nova.Math;

package Scenery is

   Horizon : constant := 128;  --  scanline where sky meets water

   procedure Build;
   procedure Update (Frame : Natural);

   --  0 = golden hour, 256 = deep dusk. Other actors read it to dim themselves.
   function Darkness return Natural;

   --  Sun position, so the ship's exhaust could glint off it
   function Sun_Y return Fixed;

end Scenery;
