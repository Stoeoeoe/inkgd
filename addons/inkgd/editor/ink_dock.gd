# warning-ignore-all:return_value_discarded

# ############################################################################ #
# Copyright © 2019-present Frédéric Maquin <fred@ephread.com>
# Licensed under the MIT License.
# See LICENSE in the project root for license information.
# ############################################################################ #

tool
extends Control

# ############################################################################ #
# Objects
# ############################################################################ #

const Configuration = preload("res://addons/inkgd/editor/configuration.gd")

# ############################################################################ #
# Properties
# ############################################################################ #

var configuration

# ############################################################################ #
# Nodes
# ############################################################################ #

var InkFileDialog = EditorFileDialog.new()

onready var TestButton = find_node("TestButton")
onready var BuildButton = find_node("BuildButton")

onready var MonoLabel = find_node("MonoLabel")
onready var MonoHBoxContainer = find_node("MonoHBoxContainer")
onready var MonoLineEdit = find_node("MonoLineEdit")
onready var MonoDialogButton = find_node("MonoDialogButton")

onready var ExecutableLineEdit = find_node("ExecutableLineEdit")
onready var ExecutableDialogButton = find_node("ExecutableDialogButton")

onready var SourceFileLineEdit = find_node("SourceFileLineEdit")
onready var SourceFileDialogButton = find_node("SourceFileDialogButton")

onready var TargetFileLineEdit = find_node("TargetFileLineEdit")
onready var TargetFileDialogButton = find_node("TargetFileDialogButton")

onready var BuildOutputLabel = find_node("BuildOutputLabel")

# ############################################################################ #
# Overrides
# ############################################################################ #

func _ready():
    configuration = Configuration.new()

    MonoLineEdit.text = configuration.mono_path
    ExecutableLineEdit.text = configuration.inklecate_path
    SourceFileLineEdit.text = configuration.source_file_path
    TargetFileLineEdit.text = configuration.target_file_path

    MonoLineEdit.connect("text_entered", self, "_mono_selected")
    ExecutableLineEdit.connect("text_entered", self, "_executable_selected")
    SourceFileLineEdit.connect("text_entered", self, "_source_file_selected")
    TargetFileLineEdit.connect("text_entered", self, "_target_file_selected")

    MonoLineEdit.connect("focus_exited", self, "_configuration_focus_exited")
    ExecutableLineEdit.connect("focus_exited", self, "_configuration_focus_exited")
    SourceFileLineEdit.connect("focus_exited", self, "_configuration_focus_exited")
    TargetFileLineEdit.connect("focus_exited", self, "_configuration_focus_exited")

    MonoDialogButton.connect("pressed", self, "_mono_button_pressed")
    ExecutableDialogButton.connect("pressed", self, "_executable_button_pressed")
    SourceFileDialogButton.connect("pressed", self, "_source_file_button_pressed")
    TargetFileDialogButton.connect("pressed", self, "_target_file_button_pressed")

    TestButton.connect("pressed", self, "_test_button_pressed")
    BuildButton.connect("pressed", self, "_build_button_pressed")
    InkFileDialog.connect("popup_hide", self, "_file_dialog_hide")

    var is_windows = _is_running_on_windows()
    MonoLabel.visible = !is_windows
    MonoHBoxContainer.visible = !is_windows

    var theme = _retrieve_base_theme()
    var source_font = theme.get_font("output_source", "EditorFonts")
    BuildOutputLabel.add_font_override("font", source_font)

    add_child(InkFileDialog)

# ############################################################################ #
# Signal Receivers
# ############################################################################ #

func _mono_button_pressed():
    _reset_file_dialog()

    InkFileDialog.connect("file_selected", self, "_mono_selected")
    InkFileDialog.set_mode(FileDialog.MODE_OPEN_FILE)
    InkFileDialog.set_access(FileDialog.ACCESS_FILESYSTEM)
    InkFileDialog.popup_centered(Vector2(1280, 800))

func _executable_button_pressed():
    _reset_file_dialog()

    InkFileDialog.connect("file_selected", self, "_executable_selected")
    InkFileDialog.set_mode(FileDialog.MODE_OPEN_FILE)
    InkFileDialog.set_access(FileDialog.ACCESS_FILESYSTEM)
    InkFileDialog.popup_centered(Vector2(1280, 800))

func _source_file_button_pressed():
    _reset_file_dialog()

    InkFileDialog.connect("file_selected", self, "_source_file_selected")
    InkFileDialog.set_mode(FileDialog.MODE_OPEN_FILE)
    InkFileDialog.set_access(FileDialog.ACCESS_FILESYSTEM)
    InkFileDialog.add_filter("*.ink;Ink source file")
    InkFileDialog.popup_centered(Vector2(1280, 800))

func _target_file_button_pressed():
    _reset_file_dialog()

    InkFileDialog.connect("file_selected", self, "_target_file_selected")
    InkFileDialog.set_mode(FileDialog.MODE_SAVE_FILE)
    InkFileDialog.set_access(FileDialog.ACCESS_FILESYSTEM)
    InkFileDialog.add_filter("*.json;Compiled Ink project")
    InkFileDialog.popup_centered(Vector2(1280, 800))

func _file_dialog_hide():
    if InkFileDialog.is_connected("file_selected", self, "_mono_selected"):
        InkFileDialog.disconnect("file_selected", self, "_mono_selected")
    elif InkFileDialog.is_connected("file_selected", self, "_source_file_selected"):
        InkFileDialog.disconnect("file_selected", self, "_source_file_selected")
    elif InkFileDialog.is_connected("file_selected", self, "_target_file_selected"):
        InkFileDialog.disconnect("file_selected", self, "_target_file_selected")
    elif InkFileDialog.is_connected("file_selected", self, "_executable_selected"):
        InkFileDialog.disconnect("file_selected", self, "_executable_selected")

func _mono_selected(path: String):
    configuration.mono_path = ProjectSettings.globalize_path(path)
    update_save_and_cleanup(configuration.mono_path, MonoLineEdit, "_mono_selected")

func _source_file_selected(path: String):
    configuration.source_file_path = ProjectSettings.localize_path(path)
    update_save_and_cleanup(configuration.source_file_path, SourceFileLineEdit, "_source_file_selected")

func _target_file_selected(path: String):
    configuration.target_file_path = ProjectSettings.localize_path(path)
    update_save_and_cleanup(configuration.target_file_path, TargetFileLineEdit, "_target_file_selected")

func _executable_selected(path: String):
    configuration.inklecate_path = ProjectSettings.globalize_path(path)
    update_save_and_cleanup(configuration.inklecate_path, ExecutableLineEdit, "_executable_selected")

func _configuration_focus_exited():
    configuration.mono_path = MonoLineEdit.text
    configuration.source_file_path = SourceFileLineEdit.text
    configuration.target_file_path = TargetFileLineEdit.text
    configuration.inklecate_path = ExecutableLineEdit.text

    configuration.persist()

func _test_button_pressed():
    BuildOutputLabel.text = "An inklecate output should appear below if the test is successful:\n\n"

    var is_windows = _is_running_on_windows()
    var output = []

    if is_windows:
        OS.execute(configuration.inklecate_path, [], true, output)
    else:
        OS.execute(configuration.mono_path, [configuration.inklecate_path], true, output)

    BuildOutputLabel.text += PoolStringArray(output).join("\n")
    BuildOutputLabel.update()

func _build_button_pressed():
    var is_windows = _is_running_on_windows()
    var output = []

    if is_windows:
        OS.execute(configuration.inklecate_path, [
                       '-o',
                       ProjectSettings.globalize_path(configuration.target_file_path),
                       ProjectSettings.globalize_path(configuration.source_file_path)
                   ], true, output)
    else:
        OS.execute(configuration.mono_path, [
                       configuration.inklecate_path, '-o',
                       ProjectSettings.globalize_path(configuration.target_file_path),
                       ProjectSettings.globalize_path(configuration.source_file_path)
                   ], true, output)

    # Outputing a BOM is inklecate's way of saying that everything went through.
    # This is fragile. There might be a better option to express the BOM, or maybe
    # check for inklecate's return code?
    #
    # On macOS the length of the BOM is 3, on Windows the length of the BOM is 0,
    # that's fairly strange.
    if output.size() == 1 && (output[0].length() == 3 || output[0].length() == 0):
        BuildOutputLabel.text = output[0] + "Compiled to: " + configuration.target_file_path
    else:
        BuildOutputLabel.text = PoolStringArray(output).join("\n")

    BuildOutputLabel.update()

# ############################################################################ #
# Private helpers
# ############################################################################ #

func _reset_file_dialog():
    InkFileDialog.current_file = ""
    InkFileDialog.clear_filters()

func update_save_and_cleanup(value, line_edit, method_name):
    line_edit.text = value
    line_edit.update()

    configuration.persist()

    if InkFileDialog.is_connected("file_selected", self, method_name):
        InkFileDialog.disconnect("file_selected", self, method_name)

func _is_running_on_windows():
    var os_name = OS.get_name()
    return (os_name == "Windows" || os_name == "UWP")

func _retrieve_base_theme():
    var parent = BuildOutputLabel
    while(parent && parent.theme == null):
        parent = parent.get_parent()

    return parent.theme
