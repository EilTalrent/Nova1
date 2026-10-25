------------------------------------------------------------------------------
--  Nova.Console : frame timing, input, debug output, randomness, power.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

package Nova.Console is

   type Button is (Up, Down, Left, Right, A, B, Start);

   --  Sleep until PRISM has drawn the current frame. Everything you wrote to
   --  video memory before this call is what appears on screen.
   procedure Wait_VSync with Inline;

   function Frame_Count return Unsigned_32 with Inline;

   function Is_Pressed (Which : Button) return Boolean;
   function Any_Pressed return Boolean;

   --  CPU load of the previous frame, 0 .. 100 %
   function CPU_Load_Percent return Natural;

   function Random return Unsigned_32 with Inline;
   function Random (Low, High : Integer) return Integer
     with Pre => Low <= High;

   --  The debug port prints on the host console running the emulator.
   procedure Debug (Text : String);
   procedure Debug (Value : Integer);
   procedure Debug_Line (Text : String);

   procedure Power_Off (Exit_Code : Unsigned_32 := 0) with No_Return;

end Nova.Console;
