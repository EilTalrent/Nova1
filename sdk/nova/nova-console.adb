with Nova.Hardware; use Nova.Hardware;
with Nova.Crash;
pragma Unreferenced (Nova.Crash);  --  linked in for every cartridge

package body Nova.Console is

   procedure Wait_VSync is
   begin
      SYS_VSync := 1;
   end Wait_VSync;

   function Frame_Count return Unsigned_32 is (SYS_Frame);

   Button_Bit : constant array (Button) of Unsigned_32 :=
     [Up => 1, Down => 2, Left => 4, Right => 8, A => 16, B => 32, Start => 64];

   function Is_Pressed (Which : Button) return Boolean is
     ((SYS_Buttons and Button_Bit (Which)) /= 0);

   function Any_Pressed return Boolean is ((SYS_Buttons and 16#7F#) /= 0);

   function CPU_Load_Percent return Natural is
     (Natural (SYS_Last_Cycles / (Cycles_Per_Frame / 100)));

   function Random return Unsigned_32 is (SYS_Random);

   function Random (Low, High : Integer) return Integer is
      Span : constant Unsigned_32 := Unsigned_32 (High - Low) + 1;
   begin
      return Low + Integer (SYS_Random mod Span);
   end Random;

   procedure Debug (Text : String) is
   begin
      for C of Text loop
         SYS_Debug := Character'Pos (C);
      end loop;
   end Debug;

   procedure Debug (Value : Integer) is
      Digits_Buf : String (1 .. 11);
      Last       : Natural := Digits_Buf'Last + 1;
      V          : Integer := Value;
   begin
      loop
         Last := Last - 1;
         Digits_Buf (Last) := Character'Val (Character'Pos ('0') + abs (V rem 10));
         V := V / 10;
         exit when V = 0;
      end loop;
      if Value < 0 then
         Debug ("-");
      end if;
      Debug (Digits_Buf (Last .. Digits_Buf'Last));
   end Debug;

   procedure Debug_Line (Text : String) is
   begin
      Debug (Text);
      SYS_Debug := 10;
   end Debug_Line;

   procedure Power_Off (Exit_Code : Unsigned_32 := 0) is
   begin
      loop
         SYS_Halt := Exit_Code;
      end loop;
   end Power_Off;

end Nova.Console;
