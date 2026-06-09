extends CanvasLayer

signal dismissed

var _label: Label
var _prompt: Label
var _bg: ColorRect
var _can_dismiss := false

func _init() -> void:
	layer = 25

func _ready() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.75)
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	add_child(_bg)

	_label = Label.new()
	_label.anchor_left = 0.1
	_label.anchor_right = 0.9
	_label.anchor_top = 0.3
	_label.anchor_bottom = 0.7
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)

	_prompt = Label.new()
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.85
	_prompt.anchor_bottom = 1.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 12)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_prompt.text = "Press any key to continue..."
	_prompt.visible = false
	add_child(_prompt)

	visible = false
	set_process_input(false)

func show_message(text: String) -> void:
	_label.text = text
	_prompt.visible = false
	_can_dismiss = false
	visible = true
	get_tree().create_timer(2.0).timeout.connect(_show_prompt, CONNECT_ONE_SHOT)

func _show_prompt() -> void:
	if not visible:
		return
	_prompt.visible = true
	_can_dismiss = true
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not visible or not _can_dismiss:
		return
	if event is InputEventMouseMotion:
		return
	if event.is_pressed():
		get_viewport().set_input_as_handled()
		visible = false
		_can_dismiss = false
		set_process_input(false)
		dismissed.emit()
