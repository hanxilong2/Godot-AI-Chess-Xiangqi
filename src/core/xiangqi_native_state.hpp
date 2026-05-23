#ifndef XIANGQI_NATIVE_STATE_HPP
#define XIANGQI_NATIVE_STATE_HPP

#include <array>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

class XiangqiNativeStateCpp : public godot::RefCounted
{
	GDCLASS(XiangqiNativeStateCpp, godot::RefCounted)

public:
	static constexpr int RED = 0;
	static constexpr int BLACK = 1;
	static constexpr int BOARD_SIZE = 90;
	static constexpr int FLAG_CAPTURE = 1 << 0;
	static constexpr char EMPTY = '\0';

private:
	std::array<char, BOARD_SIZE> board{};
	int side_to_move = RED;
	int halfmove_clock = 0;
	int fullmove_number = 1;

protected:
	static void _bind_methods();

public:
	XiangqiNativeStateCpp();

	void clear();
	void load_board(const godot::Array &board_array, int side, int halfmove, int fullmove);
	godot::Array get_board_array() const;

	int get_side_to_move() const;
	void set_side_to_move(int side);
	int get_halfmove_clock() const;
	void set_halfmove_clock(int value);
	int get_fullmove_number() const;
	void set_fullmove_number(int value);

	bool has_piece_at(int index) const;
	bool is_empty_at(int index) const;
	godot::String get_piece_at(int index) const;
	void set_piece_at(int index, const godot::String &piece_text);
	godot::String remove_piece_at(int index);

	godot::PackedInt32Array apply_move(int from_index, int to_index, const godot::String &piece_text, int flags);
	godot::PackedInt32Array undo_move(int from_index, int to_index, const godot::String &piece_text, const godot::String &captured_piece_text, int flags);

	int find_piece(const godot::String &piece_text) const;
	int find_general(int side) const;
	int get_piece_side(int index) const;
	godot::PackedInt32Array get_indices_for_side(int side) const;
	int get_piece_count() const;
	godot::Ref<XiangqiNativeStateCpp> duplicate_state() const;

	const std::array<char, BOARD_SIZE> &get_board_data() const;
	int get_side_to_move_value() const;

	static char normalize_piece(const godot::String &piece_text);
	static bool is_valid_piece(char piece);
	static godot::String piece_to_string(char piece);
	static int other_side(int side);
	static int side_from_piece(char piece);
	static char piece_type(char piece);
	static bool is_valid_index(int index);

private:
	godot::PackedInt32Array encode_move_result(int from_index, int to_index, char piece, char captured_piece, int flags) const;
};

#endif // XIANGQI_NATIVE_STATE_HPP
