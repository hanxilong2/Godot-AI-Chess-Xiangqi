using Godot;
using System;
using System.Collections.Generic;

public partial class XiangqiRulesNative : RefCounted
{
    private const int Red = 0;
    private const int Black = 1;
    private const int BoardFiles = 9;
    private const int BoardRanks = 10;
    private const int BoardSize = BoardFiles * BoardRanks;
    private const int FlagCapture = 1 << 0;
    private const int FlagCheck = 1 << 1;
    private const int FlagCheckmate = 1 << 2;
    private const int FlagSpecial = 1 << 3;
    private const char Empty = '\0';

    private static readonly StringName BoardProperty = "board";
    private static readonly StringName SideToMoveProperty = "side_to_move";
    private static readonly StringName FromIndexProperty = "from_index";
    private static readonly StringName ToIndexProperty = "to_index";

    private readonly struct MoveData
    {
        public MoveData(int from, int to, char piece, char capturedPiece, int flags)
        {
            From = from;
            To = to;
            Piece = piece;
            CapturedPiece = capturedPiece;
            Flags = flags;
        }

        public readonly int From;
        public readonly int To;
        public readonly char Piece;
        public readonly char CapturedPiece;
        public readonly int Flags;
    }

    private readonly struct StepPattern
    {
        public StepPattern(int moveFile, int moveRank, int blockFile, int blockRank)
        {
            MoveFile = moveFile;
            MoveRank = moveRank;
            BlockFile = blockFile;
            BlockRank = blockRank;
        }

        public readonly int MoveFile;
        public readonly int MoveRank;
        public readonly int BlockFile;
        public readonly int BlockRank;
    }

    private sealed class Position
    {
        public Position(char[] board)
        {
            Board = board;
        }

        public readonly char[] Board;
        public int SideToMove = Red;
    }

    private static readonly (int File, int Rank)[] OrthogonalDirections =
    {
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
    };

    private static readonly (int File, int Rank)[] AdvisorDirections =
    {
        (1, 1),
        (1, -1),
        (-1, 1),
        (-1, -1),
    };

    private static readonly StepPattern[] ElephantPatterns =
    {
        new(2, 2, 1, 1),
        new(2, -2, 1, -1),
        new(-2, 2, -1, 1),
        new(-2, -2, -1, -1),
    };

    private static readonly StepPattern[] HorsePatterns =
    {
        new(1, 2, 0, 1),
        new(-1, 2, 0, 1),
        new(1, -2, 0, -1),
        new(-1, -2, 0, -1),
        new(2, 1, 1, 0),
        new(2, -1, 1, 0),
        new(-2, 1, -1, 0),
        new(-2, -1, -1, 0),
    };

    public int implementation_stage()
    {
        return 2;
    }

    public bool rules_ready()
    {
        return true;
    }

    public int[] generate_pseudo_legal_moves(GodotObject state, int fromIndex)
    {
        if (!TryReadState(state, out var position))
        {
            return Array.Empty<int>();
        }

        return EncodeMoves(GeneratePseudoLegalMoves(position.Board, position.SideToMove, fromIndex));
    }

    public int[] generate_pseudo_legal_moves_for_side(GodotObject state, int side, int fromIndex)
    {
        if (!TryReadState(state, out var position))
        {
            return Array.Empty<int>();
        }

        return EncodeMoves(GeneratePseudoLegalMoves(position.Board, side, fromIndex));
    }

    public int[] generate_legal_moves(GodotObject state, int side, int fromIndex)
    {
        if (!TryReadState(state, out var position))
        {
            return Array.Empty<int>();
        }

        int resolvedSide = ResolveSide(position, side);
        var legalMoves = GenerateLegalMoves(position.Board, resolvedSide, fromIndex, includeCheckFlags: true);
        return EncodeMoves(legalMoves);
    }

    public bool is_legal_move(GodotObject state, GodotObject move, int side)
    {
        if (!TryReadState(state, out var position) || !TryReadMove(move, out int fromIndex, out int toIndex))
        {
            return false;
        }

        int resolvedSide = ResolveSide(position, side);
        if (!OwnsPiece(position.Board, fromIndex, resolvedSide))
        {
            return false;
        }

        var candidates = GeneratePseudoLegalMoves(position.Board, resolvedSide, fromIndex);
        foreach (var candidate in candidates)
        {
            if (candidate.From != fromIndex || candidate.To != toIndex)
            {
                continue;
            }

            if (IsMoveLegalOnBoard(position.Board, candidate, resolvedSide))
            {
                return true;
            }
        }

        return false;
    }

    public bool is_in_check(GodotObject state, int side)
    {
        if (!TryReadState(state, out var position))
        {
            return false;
        }

        return IsInCheck(position.Board, side);
    }

    public bool are_generals_facing(GodotObject state)
    {
        if (!TryReadState(state, out var position))
        {
            return false;
        }

        return AreGeneralsFacing(position.Board);
    }

    public bool has_any_legal_move(GodotObject state, int side, int fromIndex)
    {
        if (!TryReadState(state, out var position))
        {
            return false;
        }

        return HasAnyLegalMove(position.Board, ResolveSide(position, side), fromIndex);
    }

    public bool is_checkmate(GodotObject state, int side)
    {
        if (!TryReadState(state, out var position))
        {
            return false;
        }

        int resolvedSide = ResolveSide(position, side);
        return !HasAnyLegalMove(position.Board, resolvedSide, -1);
    }

    public bool is_stalemate(GodotObject state, int side)
    {
        if (!TryReadState(state, out var position))
        {
            return false;
        }

        return false;
    }

    public string get_position_status(GodotObject state, int side)
    {
        if (!TryReadState(state, out var position))
        {
            return "invalid";
        }

        int resolvedSide = ResolveSide(position, side);
        bool inCheck = IsInCheck(position.Board, resolvedSide);
        bool hasMove = HasAnyLegalMove(position.Board, resolvedSide, -1);

        if (!hasMove)
        {
            return "checkmate";
        }

        return inCheck ? "check" : "ok";
    }

    private static bool TryReadState(GodotObject state, out Position position)
    {
        if (state is XiangqiNativeState nativeState)
        {
            position = new Position(nativeState.BoardData)
            {
                SideToMove = nativeState.SideToMoveValue,
            };
            return true;
        }

        position = new Position(new char[BoardSize]);
        if (state == null)
        {
            return false;
        }

        var boardVariant = state.Get(BoardProperty);
        if (boardVariant.VariantType != Variant.Type.Array)
        {
            return false;
        }

        var boardArray = boardVariant.AsGodotArray();
        if (boardArray.Count < BoardSize)
        {
            return false;
        }

        for (int index = 0; index < BoardSize; index++)
        {
            string pieceText = boardArray[index].AsString();
            position.Board[index] = string.IsNullOrEmpty(pieceText) ? Empty : pieceText[0];
        }

        position.SideToMove = (int)state.Get(SideToMoveProperty).AsInt64();
        return true;
    }

    private static bool TryReadMove(GodotObject move, out int fromIndex, out int toIndex)
    {
        fromIndex = -1;
        toIndex = -1;
        if (move == null)
        {
            return false;
        }

        fromIndex = (int)move.Get(FromIndexProperty).AsInt64();
        toIndex = (int)move.Get(ToIndexProperty).AsInt64();
        return IsValidIndex(fromIndex) && IsValidIndex(toIndex);
    }

    private static int[] EncodeMoves(List<MoveData> moves)
    {
        var encoded = new int[moves.Count * 5];
        int writeIndex = 0;

        foreach (var move in moves)
        {
            encoded[writeIndex++] = move.From;
            encoded[writeIndex++] = move.To;
            encoded[writeIndex++] = move.Piece;
            encoded[writeIndex++] = move.CapturedPiece;
            encoded[writeIndex++] = move.Flags;
        }

        return encoded;
    }

    private static List<MoveData> GeneratePseudoLegalMoves(char[] board, int side, int fromIndex)
    {
        var moves = new List<MoveData>(96);

        if (fromIndex != -1)
        {
            if (OwnsPiece(board, fromIndex, side))
            {
                AppendPieceMoves(board, fromIndex, moves);
            }

            return moves;
        }

        for (int index = 0; index < BoardSize; index++)
        {
            if (OwnsPiece(board, index, side))
            {
                AppendPieceMoves(board, index, moves);
            }
        }

        return moves;
    }

    private static List<MoveData> GenerateLegalMoves(char[] board, int side, int fromIndex, bool includeCheckFlags)
    {
        var legalMoves = new List<MoveData>(96);
        var candidates = GeneratePseudoLegalMoves(board, side, fromIndex);

        foreach (var candidate in candidates)
        {
            if (!IsMoveLegalOnBoard(board, candidate, side))
            {
                continue;
            }

            int flags = candidate.Flags;
            if (includeCheckFlags)
            {
                ApplyMove(board, candidate, out char capturedPiece);
                int opponent = OtherSide(side);
                if (IsInCheck(board, opponent))
                {
                    flags |= FlagCheck;
                }
                if (!HasAnyLegalMove(board, opponent, -1))
                {
                    flags |= FlagCheckmate;
                }
                UndoMove(board, candidate, capturedPiece);
            }

            legalMoves.Add(new MoveData(candidate.From, candidate.To, candidate.Piece, candidate.CapturedPiece, flags));
        }

        return legalMoves;
    }

    private static bool HasAnyLegalMove(char[] board, int side, int fromIndex)
    {
        var candidates = GeneratePseudoLegalMoves(board, side, fromIndex);
        foreach (var candidate in candidates)
        {
            if (IsMoveLegalOnBoard(board, candidate, side))
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsMoveLegalOnBoard(char[] board, MoveData move, int side)
    {
        ApplyMove(board, move, out char capturedPiece);
        bool legal = !AreGeneralsFacing(board) && !IsInCheck(board, side);
        UndoMove(board, move, capturedPiece);
        return legal;
    }

    private static void ApplyMove(char[] board, MoveData move, out char capturedPiece)
    {
        capturedPiece = board[move.To];
        board[move.From] = Empty;
        board[move.To] = move.Piece;
    }

    private static void UndoMove(char[] board, MoveData move, char capturedPiece)
    {
        board[move.From] = move.Piece;
        board[move.To] = capturedPiece;
    }

    private static void AppendPieceMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        char piece = board[fromIndex];
        if (piece == Empty)
        {
            return;
        }

        switch (PieceType(piece))
        {
            case 'r':
                GenerateRookMoves(board, fromIndex, moves);
                break;
            case 'c':
                GenerateCannonMoves(board, fromIndex, moves);
                break;
            case 'h':
                GenerateHorseMoves(board, fromIndex, moves);
                break;
            case 'e':
                GenerateElephantMoves(board, fromIndex, moves);
                break;
            case 'a':
                GenerateAdvisorMoves(board, fromIndex, moves);
                break;
            case 'k':
                GenerateGeneralMoves(board, fromIndex, moves);
                break;
            case 'p':
                GenerateSoldierMoves(board, fromIndex, moves);
                break;
        }
    }

    private static void GenerateRookMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var direction in OrthogonalDirections)
        {
            int nextFile = file + direction.File;
            int nextRank = rank + direction.Rank;
            while (IsValid(nextFile, nextRank))
            {
                int toIndex = ToIndex(nextFile, nextRank);
                if (board[toIndex] == Empty)
                {
                    AppendMove(board, moves, fromIndex, toIndex);
                }
                else
                {
                    AppendMove(board, moves, fromIndex, toIndex);
                    break;
                }

                nextFile += direction.File;
                nextRank += direction.Rank;
            }
        }
    }

    private static void GenerateCannonMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var direction in OrthogonalDirections)
        {
            int nextFile = file + direction.File;
            int nextRank = rank + direction.Rank;
            bool screenFound = false;

            while (IsValid(nextFile, nextRank))
            {
                int toIndex = ToIndex(nextFile, nextRank);
                if (!screenFound)
                {
                    if (board[toIndex] == Empty)
                    {
                        AppendMove(board, moves, fromIndex, toIndex);
                    }
                    else
                    {
                        screenFound = true;
                    }
                }
                else if (board[toIndex] != Empty)
                {
                    AppendMove(board, moves, fromIndex, toIndex);
                    break;
                }

                nextFile += direction.File;
                nextRank += direction.Rank;
            }
        }
    }

    private static void GenerateHorseMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var pattern in HorsePatterns)
        {
            int legFile = file + pattern.BlockFile;
            int legRank = rank + pattern.BlockRank;
            if (!IsValid(legFile, legRank) || board[ToIndex(legFile, legRank)] != Empty)
            {
                continue;
            }

            int targetFile = file + pattern.MoveFile;
            int targetRank = rank + pattern.MoveRank;
            if (IsValid(targetFile, targetRank))
            {
                AppendMove(board, moves, fromIndex, ToIndex(targetFile, targetRank));
            }
        }
    }

    private static void GenerateElephantMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int side = SideFromPiece(board[fromIndex]);
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var pattern in ElephantPatterns)
        {
            int eyeFile = file + pattern.BlockFile;
            int eyeRank = rank + pattern.BlockRank;
            if (!IsValid(eyeFile, eyeRank) || board[ToIndex(eyeFile, eyeRank)] != Empty)
            {
                continue;
            }

            int targetFile = file + pattern.MoveFile;
            int targetRank = rank + pattern.MoveRank;
            if (!IsValid(targetFile, targetRank) || HasCrossedRiver(side, targetRank))
            {
                continue;
            }

            AppendMove(board, moves, fromIndex, ToIndex(targetFile, targetRank));
        }
    }

    private static void GenerateAdvisorMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int side = SideFromPiece(board[fromIndex]);
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var direction in AdvisorDirections)
        {
            int targetFile = file + direction.File;
            int targetRank = rank + direction.Rank;
            if (IsValid(targetFile, targetRank) && IsInPalace(side, targetFile, targetRank))
            {
                AppendMove(board, moves, fromIndex, ToIndex(targetFile, targetRank));
            }
        }
    }

    private static void GenerateGeneralMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int side = SideFromPiece(board[fromIndex]);
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);

        foreach (var direction in OrthogonalDirections)
        {
            int targetFile = file + direction.File;
            int targetRank = rank + direction.Rank;
            if (IsValid(targetFile, targetRank) && IsInPalace(side, targetFile, targetRank))
            {
                AppendMove(board, moves, fromIndex, ToIndex(targetFile, targetRank));
            }
        }

        int enemyGeneralIndex = FindGeneral(board, OtherSide(side));
        if (enemyGeneralIndex == -1 || FileOf(enemyGeneralIndex) != file)
        {
            return;
        }

        if (CountPiecesBetweenOnFile(board, file, rank, RankOf(enemyGeneralIndex)) == 0)
        {
            AppendMove(board, moves, fromIndex, enemyGeneralIndex, FlagSpecial);
        }
    }

    private static void GenerateSoldierMoves(char[] board, int fromIndex, List<MoveData> moves)
    {
        int side = SideFromPiece(board[fromIndex]);
        int file = FileOf(fromIndex);
        int rank = RankOf(fromIndex);
        int forward = side == Red ? -1 : 1;
        int forwardRank = rank + forward;

        if (IsValid(file, forwardRank))
        {
            AppendMove(board, moves, fromIndex, ToIndex(file, forwardRank));
        }

        if (!HasCrossedRiver(side, rank))
        {
            return;
        }

        int leftFile = file - 1;
        int rightFile = file + 1;
        if (IsValid(leftFile, rank))
        {
            AppendMove(board, moves, fromIndex, ToIndex(leftFile, rank));
        }

        if (IsValid(rightFile, rank))
        {
            AppendMove(board, moves, fromIndex, ToIndex(rightFile, rank));
        }
    }

    private static void AppendMove(char[] board, List<MoveData> moves, int fromIndex, int toIndex, int extraFlags = 0)
    {
        if (!IsValidIndex(fromIndex) || !IsValidIndex(toIndex))
        {
            return;
        }

        char piece = board[fromIndex];
        if (piece == Empty)
        {
            return;
        }

        char capturedPiece = board[toIndex];
        if (capturedPiece != Empty && SideFromPiece(capturedPiece) == SideFromPiece(piece))
        {
            return;
        }

        int flags = extraFlags;
        if (capturedPiece != Empty)
        {
            flags |= FlagCapture;
        }

        moves.Add(new MoveData(fromIndex, toIndex, piece, capturedPiece, flags));
    }

    private static bool IsInCheck(char[] board, int side)
    {
        int generalIndex = FindGeneral(board, side);
        if (generalIndex == -1)
        {
            return true;
        }

        return IsSquareAttacked(board, generalIndex, OtherSide(side));
    }

    private static bool IsSquareAttacked(char[] board, int squareIndex, int attackerSide)
    {
        int file = FileOf(squareIndex);
        int rank = RankOf(squareIndex);

        if (IsAttackedByRookCannonOrGeneral(board, file, rank, attackerSide))
        {
            return true;
        }

        if (IsAttackedByHorse(board, file, rank, attackerSide))
        {
            return true;
        }

        if (IsAttackedBySoldier(board, file, rank, attackerSide))
        {
            return true;
        }

        if (IsAttackedByAdvisor(board, file, rank, attackerSide))
        {
            return true;
        }

        return IsAttackedByElephant(board, file, rank, attackerSide);
    }

    private static bool IsAttackedByRookCannonOrGeneral(char[] board, int file, int rank, int attackerSide)
    {
        foreach (var direction in OrthogonalDirections)
        {
            int nextFile = file + direction.File;
            int nextRank = rank + direction.Rank;
            bool screenFound = false;

            while (IsValid(nextFile, nextRank))
            {
                int index = ToIndex(nextFile, nextRank);
                char piece = board[index];
                if (piece == Empty)
                {
                    nextFile += direction.File;
                    nextRank += direction.Rank;
                    continue;
                }

                if (!screenFound)
                {
                    if (SideFromPiece(piece) == attackerSide)
                    {
                        char type = PieceType(piece);
                        if (type == 'r')
                        {
                            return true;
                        }

                        if (type == 'k' && direction.File == 0)
                        {
                            return true;
                        }
                    }

                    screenFound = true;
                    nextFile += direction.File;
                    nextRank += direction.Rank;
                    continue;
                }

                if (SideFromPiece(piece) == attackerSide && PieceType(piece) == 'c')
                {
                    return true;
                }

                break;
            }
        }

        return false;
    }

    private static bool IsAttackedByHorse(char[] board, int file, int rank, int attackerSide)
    {
        foreach (var pattern in HorsePatterns)
        {
            int attackerFile = file - pattern.MoveFile;
            int attackerRank = rank - pattern.MoveRank;
            int legFile = attackerFile + pattern.BlockFile;
            int legRank = attackerRank + pattern.BlockRank;

            if (!IsValid(attackerFile, attackerRank) || !IsValid(legFile, legRank))
            {
                continue;
            }

            if (board[ToIndex(legFile, legRank)] != Empty)
            {
                continue;
            }

            char piece = board[ToIndex(attackerFile, attackerRank)];
            if (piece != Empty && SideFromPiece(piece) == attackerSide && PieceType(piece) == 'h')
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsAttackedBySoldier(char[] board, int file, int rank, int attackerSide)
    {
        int forwardSourceRank = attackerSide == Red ? rank + 1 : rank - 1;
        if (IsValid(file, forwardSourceRank))
        {
            char piece = board[ToIndex(file, forwardSourceRank)];
            if (piece != Empty && SideFromPiece(piece) == attackerSide && PieceType(piece) == 'p')
            {
                return true;
            }
        }

        int leftFile = file - 1;
        if (IsValid(leftFile, rank) && IsCrossedSoldier(board, leftFile, rank, attackerSide))
        {
            return true;
        }

        int rightFile = file + 1;
        return IsValid(rightFile, rank) && IsCrossedSoldier(board, rightFile, rank, attackerSide);
    }

    private static bool IsCrossedSoldier(char[] board, int file, int rank, int attackerSide)
    {
        char piece = board[ToIndex(file, rank)];
        return piece != Empty &&
            SideFromPiece(piece) == attackerSide &&
            PieceType(piece) == 'p' &&
            HasCrossedRiver(attackerSide, rank);
    }

    private static bool IsAttackedByAdvisor(char[] board, int file, int rank, int attackerSide)
    {
        foreach (var direction in AdvisorDirections)
        {
            int attackerFile = file - direction.File;
            int attackerRank = rank - direction.Rank;
            if (!IsValid(attackerFile, attackerRank) || !IsInPalace(attackerSide, attackerFile, attackerRank))
            {
                continue;
            }

            char piece = board[ToIndex(attackerFile, attackerRank)];
            if (piece != Empty && SideFromPiece(piece) == attackerSide && PieceType(piece) == 'a')
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsAttackedByElephant(char[] board, int file, int rank, int attackerSide)
    {
        foreach (var pattern in ElephantPatterns)
        {
            int attackerFile = file - pattern.MoveFile;
            int attackerRank = rank - pattern.MoveRank;
            int eyeFile = attackerFile + pattern.BlockFile;
            int eyeRank = attackerRank + pattern.BlockRank;

            if (!IsValid(attackerFile, attackerRank) || !IsValid(eyeFile, eyeRank))
            {
                continue;
            }

            if (board[ToIndex(eyeFile, eyeRank)] != Empty || HasCrossedRiver(attackerSide, rank))
            {
                continue;
            }

            char piece = board[ToIndex(attackerFile, attackerRank)];
            if (piece != Empty && SideFromPiece(piece) == attackerSide && PieceType(piece) == 'e')
            {
                return true;
            }
        }

        return false;
    }

    private static bool AreGeneralsFacing(char[] board)
    {
        int redGeneral = FindGeneral(board, Red);
        int blackGeneral = FindGeneral(board, Black);
        if (redGeneral == -1 || blackGeneral == -1 || FileOf(redGeneral) != FileOf(blackGeneral))
        {
            return false;
        }

        return CountPiecesBetweenOnFile(board, FileOf(redGeneral), RankOf(redGeneral), RankOf(blackGeneral)) == 0;
    }

    private static int CountPiecesBetweenOnFile(char[] board, int file, int rankA, int rankB)
    {
        if (rankA == rankB)
        {
            return 0;
        }

        int count = 0;
        int startRank = Math.Min(rankA, rankB) + 1;
        int endRank = Math.Max(rankA, rankB);
        for (int rank = startRank; rank < endRank; rank++)
        {
            if (board[ToIndex(file, rank)] != Empty)
            {
                count++;
            }
        }

        return count;
    }

    private static int FindGeneral(char[] board, int side)
    {
        char general = side == Red ? 'K' : 'k';
        for (int index = 0; index < BoardSize; index++)
        {
            if (board[index] == general)
            {
                return index;
            }
        }

        return -1;
    }

    private static bool OwnsPiece(char[] board, int index, int side)
    {
        return IsValidIndex(index) && board[index] != Empty && SideFromPiece(board[index]) == side;
    }

    private static int ResolveSide(Position position, int side)
    {
        return side == -1 ? position.SideToMove : side;
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

    private static bool HasCrossedRiver(int side, int rank)
    {
        return side == Red ? rank <= 4 : rank >= 5;
    }

    private static bool IsInPalace(int side, int file, int rank)
    {
        if (file < 3 || file > 5)
        {
            return false;
        }

        return side == Red ? rank >= 7 && rank <= 9 : rank >= 0 && rank <= 2;
    }

    private static bool IsValid(int file, int rank)
    {
        return file >= 0 && file < BoardFiles && rank >= 0 && rank < BoardRanks;
    }

    private static bool IsValidIndex(int index)
    {
        return index >= 0 && index < BoardSize;
    }

    private static int ToIndex(int file, int rank)
    {
        return rank * BoardFiles + file;
    }

    private static int FileOf(int index)
    {
        return index % BoardFiles;
    }

    private static int RankOf(int index)
    {
        return index / BoardFiles;
    }
}
