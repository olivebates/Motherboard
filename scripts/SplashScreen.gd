extends CanvasLayer

var _dismissed := false

func _ready() -> void:
	layer = 30

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2.ZERO
	bg.size = Vector2(800, 384)
	add_child(bg)

	var label := Label.new()
	label.text = "A Game By\nOliver T. Bates & CasterOil"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2.ZERO
	label.size = Vector2(800, 384)
	var ls := LabelSettings.new()
	ls.font_size = 18
	ls.font_color = Color.WHITE
	ls.line_spacing = 8
	label.label_settings = ls
	add_child(label)

func _input(event: InputEvent) -> void:
	if _dismissed:
		return
	var pressed := false
	if event is InputEventKey and event.pressed and not event.echo:
		pressed = true
	elif event is InputEventMouseButton and event.pressed:
		pressed = true
	elif event is InputEventJoypadButton and event.pressed:
		pressed = true
	if pressed:
		_dismiss()

func _dismiss() -> void:
	_dismissed = true
	get_viewport().set_input_as_handled()
	var player := get_tree().get_first_node_in_group("players")
	if player:
		player.unlock_movement()
	queue_free()
