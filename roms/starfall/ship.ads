------------------------------------------------------------------------------
--  STARFALL : the player's ship
--
--  Arrows fly it, A boosts. If nobody touches the pad for two seconds it
--  flies itself in a lazy figure eight, so the cartridge doubles as its own
--  attract mode.
------------------------------------------------------------------------------

package Ship is

   procedure Build;
   procedure Update (Frame : Natural);

   function Autopilot return Boolean;

end Ship;
