package body Nova.Video is

   function Mix (From, To : RGB; T : Natural) return RGB is
      function Channel (Shift : Natural) return RGB is
         A : constant Integer := Integer ((From / 2 ** Shift) mod 256);
         B : constant Integer := Integer ((To / 2 ** Shift) mod 256);
      begin
         return RGB (A + (B - A) * T / 256) * 2 ** Shift;
      end Channel;
   begin
      return Channel (16) + Channel (8) + Channel (0);
   end Mix;

   procedure Set_Entry (L : Layer; Row : Map_Row; Col : Map_Column; E : Map_Entry) is
   begin
      case L is
         when BG0 => BG0_Map (Row, Col) := E;
         when BG1 => BG1_Map (Row, Col) := E;
      end case;
   end Set_Entry;

   procedure Clear (L : Layer; Tile : Tile_Index := 0) is
   begin
      for R in Map_Row loop
         for C in Map_Column loop
            Set_Entry (L, R, C, (Tile => Tile, Flip_H => False, Flip_V => False, Bank => 0));
         end loop;
      end loop;
   end Clear;

   procedure Put_Text (L    : Layer; Row : Map_Row; Col : Map_Column;
                       Text : String; Bank : Palette_Bank := 15)
   is
      C : Map_Column := Col;
   begin
      for Ch of Text loop
         Set_Entry (L, Row, C,
                    (Tile   => Tile_Index (Character'Pos (Ch) mod 128),
                     Flip_H => False, Flip_V => False, Bank => Bank));
         exit when C = Map_Column'Last;
         C := C + 1;
      end loop;
   end Put_Text;

   procedure Put_Number (L     : Layer; Row : Map_Row; Col : Map_Column;
                         Value : Natural; Width : Positive;
                         Bank  : Palette_Bank := 15)
   is
      Buf : String (1 .. Width);
      V   : Natural := Value;
   begin
      for I in reverse Buf'Range loop
         Buf (I) := Character'Val (Character'Pos ('0') + V mod 10);
         V := V / 10;
      end loop;
      Put_Text (L, Row, Col, Buf, Bank);
   end Put_Number;

   procedure Hide_All_Sprites is
   begin
      for S in Sprite_Id loop
         OAM (S).Attr.Visible := False;
      end loop;
   end Hide_All_Sprites;

   procedure Place_Sprite (Id         : Sprite_Id;
                           X, Y       : Integer;
                           Tile       : Tile_Index;
                           Size       : Sprite_Size  := Size_8;
                           Bank       : Palette_Bank := 0;
                           Behind_BG0 : Boolean      := False;
                           Windowed   : Boolean      := False;
                           Flip_H     : Boolean      := False;
                           Flip_V     : Boolean      := False)
   is
      --  Park far-off-screen sprites at the edge of the coordinate range
      --  instead of failing a range check.
      function Clamp (V : Integer) return Coord is
        (Coord (Integer'Max (-1024, Integer'Min (1024, V))));
   begin
      OAM (Id) :=
        (X    => Clamp (X),
         Y    => Clamp (Y),
         Tile => Tile,
         Attr => (Visible    => True,
                  Flip_H     => Flip_H,
                  Flip_V     => Flip_V,
                  Size       => Size,
                  Behind_BG0 => Behind_BG0,
                  Windowed   => Windowed,
                  Bank       => Bank));
   end Place_Sprite;

   procedure Fill_Tile (T : Tile_Index; C : Color_Index) is
   begin
      for Y in 0 .. 7 loop
         for X in 0 .. 7 loop
            Tiles (T) (Y, X) := C;
         end loop;
      end loop;
   end Fill_Tile;

end Nova.Video;
