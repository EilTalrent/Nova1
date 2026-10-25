------------------------------------------------------------------------------
--  Nova.Hardware : the NOVA-1 APU as seen from Ada.
--
--  Every register, table and memory block on the console is declared here as
--  an ordinary Ada object placed at its bus address. Representation clauses
--  pin each bit field to the exact bit PRISM decodes, so writing
--
--     OAM (3).Attr.Flip_H := True;
--
--  sets bit 1 of sprite 3's attribute word, and nothing else.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;
with System;

package Nova.Hardware is
   pragma Preelaborate;

   Screen_Width  : constant := 256;
   Screen_Height : constant := 192;

   ---------------------------------------------------------------------------
   --  Basic PRISM types
   ---------------------------------------------------------------------------

   type Color_Index  is mod 256 with Size => 8;   --  0 = transparent
   type Palette_Bank is range 0 .. 15 with Size => 4;
   type Tile_Index   is range 0 .. 1023;
   type Sprite_Id    is range 0 .. 63;
   type Scanline     is range 0 .. Screen_Height - 1;
   type Coord        is range -32_768 .. 32_767 with Size => 16;

   --  24-bit colour, 0x00RRGGBB
   type RGB is mod 2 ** 32 with Size => 32;

   ---------------------------------------------------------------------------
   --  Control and scroll registers (0x2000_0000)
   ---------------------------------------------------------------------------

   type Control_Register is record
      BG0           : Boolean;
      BG1           : Boolean;
      Sprites       : Boolean;
      Line_Scroll   : Boolean;  --  BG0 per-scanline horizontal offset
      Line_Backdrop : Boolean;  --  per-scanline backdrop colour
   end record
     with Volatile_Full_Access, Size => 32;

   for Control_Register use record
      BG0           at 0 range 0 .. 0;
      BG1           at 0 range 1 .. 1;
      Sprites       at 0 range 2 .. 2;
      Line_Scroll   at 0 range 3 .. 3;
      Line_Backdrop at 0 range 4 .. 4;
   end record;

   type Brightness_Level is range 0 .. 256 with Size => 32;
   type Window_Line      is range 0 .. Screen_Height with Size => 32;

   Control      : Control_Register
     with Import, Address => System'To_Address (16#2000_0000#);
   BG0_Scroll_X : Integer_32
     with Import, Volatile, Address => System'To_Address (16#2000_0004#);
   BG0_Scroll_Y : Integer_32
     with Import, Volatile, Address => System'To_Address (16#2000_0008#);
   BG1_Scroll_X : Integer_32
     with Import, Volatile, Address => System'To_Address (16#2000_000C#);
   BG1_Scroll_Y : Integer_32
     with Import, Volatile, Address => System'To_Address (16#2000_0010#);
   Backdrop     : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#2000_0014#);
   Brightness   : Brightness_Level
     with Import, Volatile, Address => System'To_Address (16#2000_0018#);

   --  Sprites marked Windowed are only drawn on scanlines
   --  Window_Top .. Window_Bottom - 1.
   Window_Top    : Window_Line
     with Import, Volatile, Address => System'To_Address (16#2000_001C#);
   Window_Bottom : Window_Line
     with Import, Volatile, Address => System'To_Address (16#2000_0020#);

   ---------------------------------------------------------------------------
   --  Palette (0x2000_1000)
   ---------------------------------------------------------------------------

   type Palette_RAM is array (Color_Index) of RGB;
   Palette : Palette_RAM
     with Import, Volatile, Address => System'To_Address (16#2000_1000#);

   ---------------------------------------------------------------------------
   --  Sprites (OAM at 0x2000_2000)
   ---------------------------------------------------------------------------

   type Sprite_Size is (Size_8, Size_16, Size_32, Size_64);

   type Sprite_Attributes is record
      Visible    : Boolean;
      Flip_H     : Boolean;
      Flip_V     : Boolean;
      Size       : Sprite_Size;
      Behind_BG0 : Boolean;
      Windowed   : Boolean;
      Bank       : Palette_Bank;
   end record
     with Size => 16;

   for Sprite_Attributes use record
      Visible    at 0 range 0 .. 0;
      Flip_H     at 0 range 1 .. 1;
      Flip_V     at 0 range 2 .. 2;
      Size       at 0 range 3 .. 4;
      Behind_BG0 at 0 range 5 .. 5;
      Windowed   at 0 range 6 .. 6;
      Bank       at 0 range 8 .. 11;
   end record;

   type Sprite is record
      X, Y : Coord;
      Tile : Tile_Index;
      Attr : Sprite_Attributes;
   end record
     with Size => 64;

   for Sprite use record
      X    at 0 range 0 .. 15;
      Y    at 2 range 0 .. 15;
      Tile at 4 range 0 .. 15;
      Attr at 6 range 0 .. 15;
   end record;

   type Sprite_Table is array (Sprite_Id) of Sprite;
   OAM : Sprite_Table
     with Import, Volatile, Address => System'To_Address (16#2000_2000#);

   ---------------------------------------------------------------------------
   --  Raster tables (0x2000_3000, 0x2000_3200)
   ---------------------------------------------------------------------------

   type Line_Scroll_Table   is array (Scanline) of Integer_16;
   type Line_Backdrop_Table is array (Scanline) of Color_Index;

   Line_Scroll   : Line_Scroll_Table
     with Import, Volatile, Address => System'To_Address (16#2000_3000#);
   Line_Backdrop : Line_Backdrop_Table
     with Import, Volatile, Address => System'To_Address (16#2000_3200#);

   ---------------------------------------------------------------------------
   --  Tile maps (0x2000_4000, 0x2000_4800)
   ---------------------------------------------------------------------------

   type Map_Entry is record
      Tile   : Tile_Index;
      Flip_H : Boolean;
      Flip_V : Boolean;
      Bank   : Palette_Bank;
   end record
     with Size => 16;

   for Map_Entry use record
      Tile   at 0 range 0 .. 9;
      Flip_H at 0 range 10 .. 10;
      Flip_V at 0 range 11 .. 11;
      Bank   at 0 range 12 .. 15;
   end record;

   type Map_Row    is range 0 .. 31;
   type Map_Column is range 0 .. 31;
   type Tile_Map   is array (Map_Row, Map_Column) of Map_Entry
     with Component_Size => 16;

   BG0_Map : Tile_Map
     with Import, Volatile, Address => System'To_Address (16#2000_4000#);
   BG1_Map : Tile_Map
     with Import, Volatile, Address => System'To_Address (16#2000_4800#);

   ---------------------------------------------------------------------------
   --  Tile graphics (0x2001_0000). Tiles 0 .. 127 hold the character ROM.
   ---------------------------------------------------------------------------

   type Tile_Pixels is array (0 .. 7, 0 .. 7) of Color_Index;  --  (row, col)
   type Tile_RAM    is array (Tile_Index) of Tile_Pixels;

   Tiles : Tile_RAM
     with Import, Volatile, Address => System'To_Address (16#2001_0000#);

   ---------------------------------------------------------------------------
   --  System controller (0x3000_0000)
   ---------------------------------------------------------------------------

   SYS_VSync       : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0000#);
   SYS_Frame       : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0004#);
   SYS_Buttons     : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0008#);
   SYS_Debug       : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_000C#);
   SYS_Halt        : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0010#);
   SYS_Random      : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0014#);
   SYS_Last_Cycles : Unsigned_32
     with Import, Volatile, Address => System'To_Address (16#3000_0018#);

   Cycles_Per_Frame : constant := 1_000_000;

end Nova.Hardware;
