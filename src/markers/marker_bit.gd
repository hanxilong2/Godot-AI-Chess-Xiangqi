@tool
extends Node3D
class_name MarkerBit

@export var piece:int = 0
@export_custom(PropertyHint.PROPERTY_HINT_FLAGS, "bitboard") var bit:int = 0
