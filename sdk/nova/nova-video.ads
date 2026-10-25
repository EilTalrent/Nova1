------------------------------------------------------------------------------
--  Nova.Video : convenience layer over PRISM.
------------------------------------------------------------------------------

with Interfaces;    use Interfaces;
with Nova.Hardware; use Nova.Hardware;

package Nova.Video is

   type Layer is (BG0, BG1);

   function Make_RGB (R, G, B : Unsigned_8) return RGB is
     (RGB (R) * 2 ** 16 + RGB (G) * 2 ** 8 + RGB (B));

   --  Linear blend between two colours, T in 0 .. 256
   function Mix (From, To : RGB; T : Natural) return RGB
     with Pre => T <= 256;

   --  Colour index used by palette bank B for tile colour C
   function Bank_Color (B : Palette_Bank; C : Color_Index) return Color_Index is
     (Color_Index (B) * 16 + C)
     with Pre => C < 16;

   procedure Set_Entry (L : Layer; Row : Map_Row; Col : Map_Column; E : Map_Entry);
   procedure Clear (L : Layer; Tile : Tile_Index := 0);

   --  Text uses the character ROM (tiles 0 .. 127). Colour comes from palette
   --  bank Bank, entry 1. Text that runs off the right edge is clipped.
   procedure Put_Text (L    : Layer; Row : Map_Row; Col : Map_Column;
                       Text : String; Bank : Palette_Bank := 15);

   --  Zero-padded decimal number
   procedure Put_Number (L     : Layer; Row : Map_Row; Col : Map_Column;
                         Value : Natural; Width : Positive;
                         Bank  : Palette_Bank := 15);

   procedure Hide_All_Sprites;

   procedure Place_Sprite (Id         : Sprite_Id;
                           X, Y       : Integer;
                           Tile       : Tile_Index;
                           Size       : Sprite_Size  := Size_8;
                           Bank       : Palette_Bank := 0;
                           Behind_BG0 : Boolean      := False;
                           Windowed   : Boolean      := False;
                           Flip_H     : Boolean      := False;
                           Flip_V     : Boolean      := False);

   procedure Fill_Tile (T : Tile_Index; C : Color_Index);

end Nova.Video;
