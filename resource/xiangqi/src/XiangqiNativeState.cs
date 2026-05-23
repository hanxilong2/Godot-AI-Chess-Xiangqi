using Godot;
using GodotArray = Godot.Collections.Array;
using System;
using System.Collections.Generic;

public partial class XiangqiNativeState : RefCounted
{
    private const int Red = 0;
    private const int Black = 1;
    private const int BoardSize = 90;
    private const int FlagCapture = 1 << 0;
    private const char Empty = '\0';

    private readonly char[] _board = new char[BoardSize];
    private int _sideToMove = Red;
    private int _halfmoveClock;
    private int _fullmoveNumber = 1;

    internal char[] BoardData => _board;
    internal int SideToMoveValue => _sideToMove;

    public void clear()
    {
        Array.Fill(_board, Empty);
        _sideToMove = Red;
        _halfmoveClock = 0;
        _fullmoveNumber = 1;
    }

    public void load_board(GodotArray boardArray, int sideToMove, int halfmoveClock, int fullmoveNumber)
    {
        Array.Fill(_board, Empty);
        int limit = Math.Min(BoardSize, boardArray.Count);
        for (int index = 0; index < limit; index++)
        {
            _board[index] = NormalizePiece(boardArray[index].AsString());
        }

        set_side_to_move(sideToMove);
        _halfmoveClock = Math.Max(0, halfmoveClock);
        _fullmoveNumber = Math.Max(1, fullmoveNumber);
    }

    public GodotArray get_board_array()
    {
        var result = new GodotArray();
        for (int index = 0; index < BoardSize; index++)
        {
            result.Add(PieceToString(_board[index]));
        }

        return result;
    }

    public int get_side_to_move()
    {
        return _sideToMove;
    }

    public void set_side_to_move(int side)
    {
        _sideToMove = side == Red ? Red : Black;
    }

    public int get_halfmove_clock()
    {
        return _halfmoveClock;
    }

    public void set_halfmove_clock(int value)
    {
        _halfmoveClock = Math.Max(0, value);
    }

    public int get_fullmove_number()
    {
        return _fullmoveNumber;
    }

    public void set_fullmove_number(int value)
    {
        _fullmoveNumber = Math.Max(1, value);
    }

    public bool has_piece_at(int index)
    {
        return IsValidIndex(index) && _board[index] != Empty;
    }

    public bool is_empty_at(int index)
    {
        return !has_piece_at(index);
    }

    public string get_piece_at(int index)
    {
        if (!IsValidIndex(index))
        {
            return string.Empty;
        }

        return PieceToString(_board[index]);
    }

    public void set_piece_at(int index, string pieceText)
    {
        if (!IsValidIndex(index))
        {
            return;
        }

        _board[index] = NormalizePiece(pieceText);
    }

    public string remove_piece_at(int index)
    {
        if (!IsValidIndex(index))
        {
            return string.Empty;
        }

        char removed = _board[index];
        _board[index] = Empty;
        return PieceToString(removed);
    }

    public int[] apply_move(int fromIndex, int toIndex, string pieceText, int flags)
    {
        if (!IsValidIndex(fromIndex) || !IsValidIndex(toIndex))
        {
            return EncodeMoveResult(fromIndex, toIndex, Empty, Empty, flags);
        }

        char piece = NormalizePiece(pieceText);
        if (piece == Empty)
        {
            piece = _board[fromIndex];
        }

        if (piece == Empty)
        {
            return EncodeMoveResult(fromIndex, toIndex, Empty, Empty, flags);
        }

        char capturedPiece = _board[toIndex];
        if (capturedPiece != Empty)
        {
            flags |= FlagCapture;
        }

        _board[fromIndex] = Empty;
        _board[toIndex] = piece;
        _halfmoveClock = capturedPiece != Empty || PieceType(piece) == 'p' ? 0 : _halfmoveClock + 1;

        if (_sideToMove == Black)
        {
            _fullmoveNumber++;
        }

        _sideToMove = OtherSide(_sideToMove);
        return EncodeMoveResult(fromIndex, toIndex, piece, capturedPiece, flags);
    }

    public int[] undo_move(int fromIndex, int toIndex, string pieceText, string capturedPieceText, int flags)
    {
        char piece = NormalizePiece(pieceText);
        char capturedPiece = NormalizePiece(capturedPieceText);

        if (IsValidIndex(fromIndex) && IsValidIndex(toIndex) && piece != Empty)
        {
            _board[fromIndex] = piece;
            _board[toIndex] = capturedPiece;
        }

        if (_sideToMove == Red && _fullmoveNumber > 1)
        {
            _fullmoveNumber--;
        }

        _sideToMove = OtherSide(_sideToMove);
        _halfmoveClock = 0;
        return EncodeMoveResult(fromIndex, toIndex, piece, capturedPiece, flags);
    }

    public int find_piece(string pieceText)
    {
        char piece = NormalizePiece(pieceText);
        if (piece == Empty)
        {
            return -1;
        }

        for (int index = 0; index < BoardSize; index++)
        {
            if (_board[index] == piece)
            {
                return index;
            }
        }

        return -1;
    }

    public int find_general(int side)
    {
        return find_piece(side == Red ? "K" : "k");
    }

    public int get_piece_side(int index)
    {
        if (!IsValidIndex(index) || _board[index] == Empty)
        {
            return Red;
        }

        return SideFromPiece(_board[index]);
    }

    public int[] get_indices_for_side(int side)
    {
        var indices = new List<int>(16);
        for (int index = 0; index < BoardSize; index++)
        {
            if (_board[index] != Empty && SideFromPiece(_board[index]) == side)
            {
                indices.Add(index);
            }
        }

        return indices.ToArray();
    }

    public int get_piece_count()
    {
        int count = 0;
        for (int index = 0; index < BoardSize; index++)
        {
            if (_board[index] != Empty)
            {
                count++;
            }
        }

        return count;
    }

    public XiangqiNativeState duplicate_state()
    {
        var copy = new XiangqiNativeState();
        Array.Copy(_board, copy._board, BoardSize);
        copy._sideToMove = _sideToMove;
        copy._halfmoveClock = _halfmoveClock;
        copy._fullmoveNumber = _fullmoveNumber;
        return copy;
    }

    private int[] EncodeMoveResult(int fromIndex, int toIndex, char piece, char capturedPiece, int flags)
    {
        return new[]
        {
            fromIndex,
            toIndex,
            piece,
            capturedPiece,
            flags,
            _sideToMove,
            _halfmoveClock,
            _fullmoveNumber,
        };
    }

    private static char NormalizePiece(string pieceText)
    {
        if (string.IsNullOrEmpty(pieceText))
        {
            return Empty;
        }

        char piece = pieceText[0];
        return IsValidPiece(piece) ? piece : Empty;
    }

    private static bool IsValidPiece(char piece)
    {
        return PieceType(piece) switch
        {
            'k' or 'a' or 'e' or 'h' or 'r' or 'c' or 'p' => true,
            _ => false,
        };
    }

    private static string PieceToString(char piece)
    {
        return piece == Empty ? string.Empty : piece.ToString();
    }

    private static int OtherSide(int side)
    {
        return side == Red ? Black : Red;
    }

    private static int SideFromPiece(char piece)
    {
        return char.IsUpper(piece) ? Red : Black;
    }

    private static char PieceType(char piece)
    {
        return char.ToLowerInvariant(piece);
    }

    private static bool IsValidIndex(int index)
    {
        return index >= 0 && index < BoardSize;
    }
}
