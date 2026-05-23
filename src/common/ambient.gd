extends Node

var current_audio_stream:AudioStreamPlayer = null
var transition_tween:Tween = null

func _ready() -> void:
	if !tree_exiting.is_connected(_cleanup_for_exit):
		tree_exiting.connect(_cleanup_for_exit, CONNECT_ONE_SHOT)
	if !get_tree().root.tree_exiting.is_connected(_cleanup_for_exit):
		get_tree().root.tree_exiting.connect(_cleanup_for_exit, CONNECT_ONE_SHOT)

func _cleanup_for_exit() -> void:
	if transition_tween && transition_tween.is_running():
		transition_tween.kill()
	transition_tween = null
	for child:Node in get_children():
		var audio_player := child as AudioStreamPlayer
		if audio_player == null:
			continue
		audio_player.stop()
		audio_player.stream = null
		remove_child(audio_player)
		audio_player.free()
	current_audio_stream = null

func clear_environment_sound() -> void:
	_cleanup_for_exit()

func _exit_tree() -> void:
	_cleanup_for_exit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_for_exit()

func change_environment_sound(audio_stream:AudioStream) -> void:
	if is_instance_valid(current_audio_stream) && audio_stream == current_audio_stream.stream:
		return
	var next_audio_stream:AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(next_audio_stream)
	next_audio_stream.stream = audio_stream
	next_audio_stream.bus = &"Ambient"
	next_audio_stream.play()
	if is_instance_valid(current_audio_stream):
		next_audio_stream.volume_linear = 0
		if transition_tween && transition_tween.is_running():
			transition_tween.kill()
		transition_tween = create_tween()
		transition_tween.tween_property(next_audio_stream, "volume_linear", 1, 0.5)
		transition_tween.set_parallel(true)
		transition_tween.tween_property(current_audio_stream, "volume_linear", 0, 0.5)
		transition_tween.set_parallel(false)
		transition_tween.tween_callback(current_audio_stream.queue_free)
	else:
		next_audio_stream.volume_linear = 1
		transition_tween = null
	current_audio_stream = next_audio_stream
