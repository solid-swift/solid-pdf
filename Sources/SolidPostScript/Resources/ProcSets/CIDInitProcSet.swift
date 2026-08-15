//
//  CIDInitProcSet.swift
//
//
//  Created by Kevin Wooten on 7/9/24.
//

import Foundation

/// A PostScript cidinit proc set.
public enum CIDInitProcSet: ProcSet {

  /// The ``name`` value.
  public var name: String { "CIDInit" }

  /// Performs the ``load`` operation.
  public func load() -> String {
    #"""

    /beginbfchar {    % <count> beginbfchar -
      pop mark
    } bind def

    /endbfchar {      % [ <code> <to_code|charname> ... endbfchar
      ] [ //true      % [<da><ta>] [ true
      3 -1 roll       % [ true [<da><ta>]
      {
        exch {
          //false     % [ <da> false
        } {           % [ <da> <ta>
          .addbfchar  % [ prefix params key value font_index
          //true
        } ifelse
      } forall
      pop
      1 .appendmap
    } bind def

    /beginbfrange {   % <count> beginbfrange -
      pop mark
    } bind def

    /endbfrange {     % <code_lo> <code_hi> <to_code|(charname*)> ...
                      %   endbfrange -
      ] [ 0           % [<da><ta><set>] [ 0
      3 -1 roll       % [ 0 [<da><ta><set>]
      {
        exch          % [ <da> 0
        { 1 2
          {
            dup type dup /arraytype eq exch /packedarraytype eq or {
                        % Array value, split up.
              exch pop {
                        % Stack: code to_code|charname
                1 index exch .addbfchar
                        % Increment the code.  As noted above, we require
                        % that only the last byte vary, but we still must
                        % mask it after incrementing, in case the last
                        % value was 0xff.
                        % Stack: code prefix params key value fontindex
                6 -1 roll dup length string copy
                dup dup length 1 sub 2 copy get 1 add 255 and put
              } forall pop
            } {
                        % Single value, handle directly.
              .addbfrange
            } ifelse
            0
          }
        } exch get exec
      } forall
      pop
      1 .appendmap
    } bind def

    /.addbfchar {   % <code> <to_code|charname> .addbfchar
                    %   <prefix> <params> <key> <value> <font_index>
      1 index exch .addbfrange
    } bind def

    /.addbfrange {  % <code_lo> <code_hi> <to_code|charname>
                    %   .addbfrange <<same as .addbfchar>>
      4 string dup 3
      3 index type /nametype eq {
        2 index 2 1 put % dst = CODE_VALUE_GLYPH, see gxfcmap.h .
        4 -1 roll 1 array astore 4 1 roll 4
      } {
        2 index 2 2 put % dst = CODE_VALUE_CHARS, see gxfcmap.h .
        3 index length
      } ifelse put
                        % Stack: code_lo code_hi value params
      3 index 3 index eq {
                        % Single value.
        3 -1 roll pop exch () exch
      } {
                        % Range.
        dup 0 4 index length put
        dup 1 1 put
        4 2 roll
        1 index dup length 1 sub 0 exch getinterval 5 1 roll  % prefix
                        % Stack: prefix value params code_lo code_hi
        concatstrings
        3 -1 roll
      } ifelse
      .FontIndex
    } bind def

    /.appendmap {   % -mark- <elt> ... <array#> .appendmap -
      .TempMaps exch get counttomark 1 add 1 roll
      ] 1 index length exch put
    } bind def

    /begincodespacerange {  % <count> begincodespacerange -
      pop mark
    } bind def

    /endcodespacerange {  % <code_lo> <code_hi> ... endcodespacerange -
      0 .appendmap
    } bind def

    /begincmap {    % - begincmap -
      /.CodeMapData [[[]] [[]] [[]]] def
      /FontMatrices [] def
      /.FontIndex 0 def
      /.TempMaps [20 dict 50 dict 50 dict] def
      /CodeMap //null def   % for .buildcmap
    } bind def

    /endcmap {    % - endcmap -
      //.rewriteTempMapsNotDef exec

      /.CodeMapData dup load [ exch
        .TempMaps aload pop begin begin begin
        {
          [ exch aload pop
            0 1 currentdict length 1 sub {
              currentdict exch get
            } for
          ]
          end
        } forall
      ] .endmap def

      currentdict /.TempMaps undef
      /FontMatrices FontMatrices .endmap def
    } bind def

    /.rewriteTempMapsNotDef {
      %
      % Before building .CodeMapData from .TempMaps,
      % we need to replace dst type codes in the notdef map with the value 3,
      % which corresponds to CODE_VALUE_NOTDEF, see gxfcmap.h .
      %
      .TempMaps 2 get
      dup length 0 gt {
        0 get
        1 5 2 index length 1 sub {
          { 1 index exch get 2 3 put } stopped
        } for
      } if
      pop
    } bind def

    """#
  }
}
