with Nova.Hardware; use Nova.Hardware;
with Nova.Console;

package body Nova.Crash is

   procedure Last_Chance_Handler (Source_Location : System.Address; Line : Integer) is
      --  The location is a NUL-terminated C string ("file.adb").
      type C_Chars is array (1 .. 64) of Character;
      File : C_Chars with Import, Address => Source_Location;
      Len  : Natural := 0;

      procedure Put (Row : Map_Row; Col : in out Map_Column; Text : String) is
      begin
         for C of Text loop
            BG1_Map (Row, Col) :=
              (Tile => Tile_Index (Character'Pos (C) mod 128), Flip_H => False,
               Flip_V => False, Bank => 15);
            exit when Col = Map_Column'Last;
            Col := Col + 1;
         end loop;
      end Put;

      Col : Map_Column;
      Num : String (1 .. 6) := "      ";
      N   : Natural := abs Line;
      P   : Natural := Num'Last;
   begin
      while Len < C_Chars'Last and then File (Len + 1) /= ASCII.NUL loop
         Len := Len + 1;
      end loop;
      loop
         Num (P) := Character'Val (Character'Pos ('0') + N mod 10);
         N := N / 10;
         exit when N = 0 or P = 1;
         P := P - 1;
      end loop;

      if Line > 0 then
         Nova.Console.Debug ("*** ADA CHECK FAILED at ");
         Nova.Console.Debug (String (File (1 .. Len)));
         Nova.Console.Debug (":");
         Nova.Console.Debug_Line (Num (P .. Num'Last));
      else
         Nova.Console.Debug ("*** ADA ASSERTION: ");
         Nova.Console.Debug_Line (String (File (1 .. Len)));
      end if;

      --  Red screen, white text, BG1 only.
      Control := (BG1 => True, others => False);
      BG1_Scroll_X := 0;
      BG1_Scroll_Y := 0;
      Brightness := 256;
      Backdrop := 0;
      Palette (0) := 16#00_6A_10_18#;
      Palette (15 * 16 + 1) := 16#00_FF_F0_E0#;
      for R in Map_Row loop
         for C in Map_Column loop
            BG1_Map (R, C) := (Tile => 0, Flip_H => False, Flip_V => False, Bank => 0);
         end loop;
      end loop;

      Col := 2;  Put (4, Col, "*** CARTRIDGE FAULT ***");
      if Line > 0 then
         Col := 2;  Put (7, Col, "AN ADA RUNTIME CHECK FAILED");
         Col := 2;  Put (9, Col, "FILE: ");  Put (9, Col, String (File (1 .. Len)));
         Col := 2;  Put (10, Col, "LINE: "); Put (10, Col, Num (P .. Num'Last));
      else
         --  An assertion or contract: the message names the place. Wrap it.
         Col := 2;  Put (7, Col, "AN ADA CONTRACT WAS BROKEN");
         for Part in 0 .. 2 loop
            declare
               First : constant Positive := 1 + Part * 28;
               Last  : constant Natural  := Natural'Min (Len, First + 27);
            begin
               exit when First > Len;
               Col := 2;
               Put (Map_Row (9 + Part), Col, String (File (First .. Last)));
            end;
         end loop;
      end if;
      Col := 2;  Put (13, Col, "THE CARTRIDGE HAS BEEN HALTED");
      Col := 2;  Put (14, Col, "BEFORE IT COULD DO DAMAGE.");

      Nova.Console.Power_Off (Crash_Exit_Code);
   end Last_Chance_Handler;

end Nova.Crash;
