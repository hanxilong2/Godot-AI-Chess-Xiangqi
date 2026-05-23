#ifndef XIANGQI_RULES_NATIVE_HPP
#define XIANGQI_RULES_NATIVE_HPP

#include <array>
#include <vector>

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "xiangqi_native_state.hpp"

class XiangqiRulesNativeCpp : public godot::RefCounted
{
	GDCLASS(XiangqiRulesNativeCpp, godot::RefCounted)

private:
	static constexpr int RED = XiangqiNativeStateCpp::RED;
	static constexpr int BLACK = XiangqiNativeStateCpp::BLACK;
	static constexpr int BOARD_FILES = 9;
	static constexpr int BOARD_RANKS = 10;
	static constexpr int BOARD_SIZE = BOARD_FILES * BOARD_RANKS;
	static constexpr int FLAG_CAPTURE = 1 << 0;
	static constexpr int FLAG_CHECK = 1 << 1;
	static constexpr int FLAG_CHECKMATE = 1 << 2;
	static constexpr int FLAG_SPECIAL = 1 << 3;
	static constexpr char EMPTY = XiangqiNativeStateCpp::EMPTY;

	struct MoveData
	{
		int from = -1;
		int to = -1;
		char piece = EMPTY;
		char captured_piece = EMPTY;
		int flags = 0;
	};

public:
	struct Direction
	{
		int file = 0;
		int rank = 0;
	};

	struct StepPattern
	{
		int move_file = 0;
		int move_rank = 0;
		int block_file = 0;
		int block_rank = 0;
	};

private:
	struct Position
	{
		std::array<char, BOARD_SIZE> board{};
		int side_to_move = RED;
	};

protected:
	static void _bind_methods();

public:
	int implementation_stage() const;
	bool rules_ready() const;

	godot::PackedInt32Array generate_pseudo_legal_moves(godot::Object *state, int from_index) const;
	godot::PackedInt32Array generate_pseudo_legal_moves_for_side(godot::Object *state, int side, int from_index) const;
	godot::PackedInt32Array generate_legal_moves(godot::Object *state, int side, int from_index) const;
	bool is_legal_move(godot::Object *state, godot::Object *move, int side) const;
	bool is_in_check(godot::Object *state, int side) const;
	bool are_generals_facing(godot::Object *state) const;
	bool has_any_legal_move(godot::Object *state, int side, int from_index) const;
	bool is_checkmate(godot::Object *state, int side) const;
	bool is_stalemate(godot::Object *state, int side) const;
	godot::String get_position_status(godot::Object *state, int side) const;

private:
	static bool try_read_state(godot::Object *state, Position &position);
	static bool try_read_move(godot::Object *move, int &from_index, int &to_index);
	static godot::PackedInt32Array encode_moves(const std::vector<MoveData> &moves);

	static std::vector<MoveData> generate_pseudo_legal_moves_for_board(const std::array<char, BOARD_SIZE> &board, int side, int from_index);
	static std::vector<MoveData> generate_legal_moves_for_board(std::array<char, BOARD_SIZE> &board, int side, int from_index, bool include_check_flags);
	static bool has_any_legal_move_on_board(std::array<char, BOARD_SIZE> &board, int side, int from_index);
	static bool is_move_legal_on_board(std::array<char, BOARD_SIZE> &board, const MoveData &move, int side);
	static void apply_move(std::array<char, BOARD_SIZE> &board, const MoveData &move, char &captured_piece);
	static void undo_move(std::array<char, BOARD_SIZE> &board, const MoveData &move, char captured_piece);

	static void append_piece_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_rook_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_cannon_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_horse_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_elephant_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_advisor_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_general_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void generate_soldier_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves);
	static void append_move(const std::array<char, BOARD_SIZE> &board, std::vector<MoveData> &moves, int from_index, int to_index, int extra_flags = 0);

	static bool is_in_check_on_board(const std::array<char, BOARD_SIZE> &board, int side);
	static bool is_square_attacked(const std::array<char, BOARD_SIZE> &board, int square_index, int attacker_side);
	static bool is_attacked_by_rook_cannon_or_general(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool is_attacked_by_horse(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool is_attacked_by_soldier(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool is_crossed_soldier(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool is_attacked_by_advisor(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool is_attacked_by_elephant(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side);
	static bool are_generals_facing_on_board(const std::array<char, BOARD_SIZE> &board);
	static int count_pieces_between_on_file(const std::array<char, BOARD_SIZE> &board, int file, int rank_a, int rank_b);
	static int find_general(const std::array<char, BOARD_SIZE> &board, int side);
	static bool owns_piece(const std::array<char, BOARD_SIZE> &board, int index, int side);

	static int resolve_side(const Position &position, int side);
	static int other_side(int side);
	static int side_from_piece(char piece);
	static char piece_type(char piece);
	static bool has_crossed_river(int side, int rank);
	static bool is_in_palace(int side, int file, int rank);
	static bool is_valid(int file, int rank);
	static bool is_valid_index(int index);
	static int to_index(int file, int rank);
	static int file_of(int index);
	static int rank_of(int index);
};

#endif // XIANGQI_RULES_NATIVE_HPP
