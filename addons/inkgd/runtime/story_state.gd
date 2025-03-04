# warning-ignore-all:shadowed_variable
# warning-ignore-all:unused_class_variable
# ############################################################################ #
# Copyright © 2015-present inkle Ltd.
# Copyright © 2019-present Frédéric Maquin <fred@ephread.com>
# All Rights Reserved
#
# This file is part of inkgd.
# inkgd is licensed under the terms of the MIT license.
# ############################################################################ #

extends "res://addons/inkgd/runtime/ink_base.gd"

# ############################################################################ #
# Self-reference
# ############################################################################ #

var StoryState = weakref(load("res://addons/inkgd/runtime/story_state.gd"))

# ############################################################################ #
# Imports
# ############################################################################ #

var PushPopType = preload("res://addons/inkgd/runtime/push_pop.gd").PushPopType
var Pointer = load("res://addons/inkgd/runtime/pointer.gd")
var CallStack = load("res://addons/inkgd/runtime/call_stack.gd")
var VariablesState = load("res://addons/inkgd/runtime/variables_state.gd")
var InkPath = load("res://addons/inkgd/runtime/ink_path.gd")
var Ink = load("res://addons/inkgd/runtime/value.gd")
var ControlCommand = load("res://addons/inkgd/runtime/control_command.gd")
var SimpleJson = load("res://addons/inkgd/runtime/simple_json.gd")

# ############################################################################ #

const INK_SAVE_STATE_VERSION = 8
const MIN_COMPATIBLE_LOAD_VERSION = 8

# () -> String
func to_json():
    return JSON.print(self.json_token)

# (String) -> void
func load_json(json):
    self.json_token = SimpleJson.text_to_dictionary(json)

# (String) -> int
func visit_count_at_path_string(path_string):
    if visit_counts.has(path_string):
        return visit_counts[path_string]

    return 0

var callstack_depth setget , get_callstack_depth # int
func get_callstack_depth():
    return self.callstack.depth

var output_stream setget , get_output_stream # Array<InkObject>
func get_output_stream():
    return self._output_stream

var current_choices setget , get_current_choices # Array<Choice>
func get_current_choices():
    if self.can_continue: return []
    return self._current_choices

var generated_choices setget , get_generated_choices # Array<Choice>
func get_generated_choices():
    return self._current_choices

var current_errors = null # Array<String>
var current_warnings = null # Array<String>
var variables_state = null # VariableState
var callstack = null # CallStack
var evaluation_stack = null # Array<InkObject>
var diverted_pointer = Pointer.null() # Pointer
var visit_counts = null # Dictionary<String, int>
var turn_indices = null # Dictionary<String, int>
var current_turn_index = 0 # int
var story_seed = 0 # int
var previous_random = 0 # int
var did_safe_exit = false # bool

var story = null # WeakRef<Story>

var current_path_string setget , get_current_path_string # String
func get_current_path_string():
    var pointer = self.current_pointer
    if pointer.is_null:
        return null
    else:
        return pointer.path.to_string()

var current_pointer setget set_current_pointer, get_current_pointer # Pointer
func get_current_pointer():
    var pointer = self.callstack.current_element.current_pointer
    return self.callstack.current_element.current_pointer.duplicate()

func set_current_pointer(value):
    var current_element = self.callstack.current_element
    current_element.current_pointer = value.duplicate()

var previous_pointer setget set_previous_pointer, get_previous_pointer # Pointer
func get_previous_pointer():
    return self.callstack.current_thread.previous_pointer.duplicate()

func set_previous_pointer(value):
    var current_thread = self.callstack.current_thread
    current_thread.previous_pointer = value.duplicate()

var can_continue setget , get_can_continue # bool
func get_can_continue():
    return !self.current_pointer.is_null && !self.has_error

var has_error setget , get_has_error # bool
func get_has_error():
    return self.current_errors != null && self.current_errors.size() > 0

var has_warning setget , get_has_warning # bool
func get_has_warning():
    return self.current_warnings != null && self.current_warnings.size() > 0

var current_text setget , get_current_text # String
func get_current_text():
    if self._output_stream_text_dirty:
        var _str = ""

        for output_obj in _output_stream:
            var text_content = Utils.as_or_null(output_obj, "StringValue")
            if text_content != null:
                _str += text_content.value

        self._current_text = self.clean_output_whitespace(_str)

        self._output_stream_text_dirty = false

    return self._current_text

var _current_text = null # String

# (String) -> String
func clean_output_whitespace(str_to_clean):
    var _str = ""

    var current_whitespace_start = -1
    var start_of_line = 0

    var i = 0
    while(i < str_to_clean.length()):
        var c = str_to_clean[i]

        var is_inline_whitespace = (c == " " || c == "\t")

        if is_inline_whitespace && current_whitespace_start == -1:
            current_whitespace_start = i

        if !is_inline_whitespace:
            if (c != "\n" && current_whitespace_start > 0 &&
                current_whitespace_start != start_of_line):
                _str += " "

            current_whitespace_start = -1

        if c == "\n":
            start_of_line = i + 1

        if !is_inline_whitespace:
            _str += c

        i += 1

    return _str

var current_tags setget , get_current_tags # Array<String>
func get_current_tags():
    if self._output_stream_tags_dirty:
        self._current_tags = [] # Array<String>

        for output_obj in self._output_stream:
            var tag = Utils.as_or_null(output_obj, "Tag")
            if tag != null:
                self._current_tags.append(tag.text)

        self._output_stream_tags_dirty = false

    return self._current_tags

var _current_tags # Array<String>

var in_expression_evaluation setget set_in_expression_evaluation, get_in_expression_evaluation # bool
func get_in_expression_evaluation():
    return self.callstack.current_element.in_expression_evaluation
func set_in_expression_evaluation(value):
    var current_element = self.callstack.current_element
    current_element.in_expression_evaluation = value

# (Story) -> StoryState
func _init(story):
    get_json()

    self.story = weakref(story)

    self._output_stream = [] # Array<InkObject>
    self.output_stream_dirty()

    self.evaluation_stack = [] # Array<InkObject>

    self.callstack = CallStack.new(self.story.get_ref())
    self.variables_state = VariablesState.new(callstack, self.story.get_ref().list_definitions)

    self.visit_counts = {} # Dictionary<String, int>
    self.turn_indices = {} # Dictionary<String, int>
    self.current_turn_index = -1

    randomize()
    self.story_seed = randi() % 100
    self.previous_random = 0

    self._current_choices = [] # Array<Choice>

    self.go_to_start()

# () -> void
func go_to_start():
    var current_element = self.callstack.current_element
    current_element.current_pointer = Pointer.start_of(story.get_ref().main_content_container)

# () -> StoryState
func copy():
    var copy = StoryState.get_ref().new(self.story.get_ref())

    copy._output_stream += self._output_stream
    self.output_stream_dirty()

    copy._current_choices += self._current_choices

    if self.has_error:
        copy.current_errors = [] # Array<String>
        copy.current_errors += self.current_errors

    if self.has_warning:
        copy.current_warnings = [] # Array<String>
        copy.current_warnings += self.current_warnings

    copy.callstack = CallStack.new(self.callstack)

    copy.variables_state = VariablesState.new(copy.callstack, self.story.get_ref().list_definitions)
    copy.variables_state.copy_from(self.variables_state)

    copy.evaluation_stack += self.evaluation_stack

    if !diverted_pointer.is_null:
        copy.diverted_pointer = self.diverted_pointer.duplicate()

    copy.previous_pointer = self.previous_pointer.duplicate()

    copy.visit_counts = self.visit_counts.duplicate() # Dictionary<String, int>
    copy.turn_indices = self.turn_indices.duplicate() # Dictionary<String, int>
    copy.current_turn_index = self.current_turn_index
    copy.story_seed = self.story_seed
    copy.previous_random = self.previous_random

    copy.did_safe_exit = self.did_safe_exit

    return copy

var json_token setget set_json_token, get_json_token # Dictionary<String, Variant>
func get_json_token():
    var obj = {} # Dictionary<String, Variant>

    var choice_threads = null # Dictionary<String, Variant>
    for c in self._current_choices:
        c.original_thread_index = c.thread_at_generation.thread_index

        if self.callstack.thread_with_index(c.original_thread_index) == null:
            if choice_threads == null:
                choice_threads = {} # Dictionary<String, Variant>

            choice_threads[str(c.original_thread_index)] = c.thread_at_generation.json_token

    if choice_threads != null:
        obj["choiceThreads"] = choice_threads


    obj["callstackThreads"] = self.callstack.get_json_token()
    obj["variablesState"] = self.variables_state.json_token

    obj["evalStack"] = Json.list_to_jarray(self.evaluation_stack)

    obj["outputStream"] = Json.list_to_jarray(self._output_stream)

    obj["currentChoices"] = Json.list_to_jarray(self._current_choices)

    if !self.diverted_pointer.is_null:
        obj ["currentDivertTarget"] = self.diverted_pointer.path.components_string

    obj["visitCounts"] = Json.int_dictionary_to_jobject(self.visit_counts)
    obj["turnIndices"] = Json.int_dictionary_to_jobject(self.turn_indices)
    obj["turnIdx"] = self.current_turn_index
    obj["storySeed"] = self.story_seed
    obj["previousRandom"] = self.previous_random

    obj["inkSaveVersion"] = INK_SAVE_STATE_VERSION

    obj["inkFormatVersion"] = self.story.get_ref().INK_VERSION_CURRENT

    return obj

func set_json_token(value):
    var jobject = value

    var jsave_version = null # Variant
    if !jobject.has("inkSaveVersion"):
        Utils.throw_story_exception("ink save format incorrect, can't load.")
        return
    else:
        jsave_version = int(jobject["inkSaveVersion"])
        if jsave_version < MIN_COMPATIBLE_LOAD_VERSION:
            Utils.throw_story_exception(str(
                "Ink save format isn't compatible with the current version (saw '",
                jsave_version, "', but minimum is ", MIN_COMPATIBLE_LOAD_VERSION,
                "), so can't load."
            ))
            return

    self.callstack.set_json_token(jobject["callstackThreads"], self.story.get_ref())

    var variable_state = self.variables_state
    variable_state.json_token = jobject["variablesState"]

    self.evaluation_stack = Json.jarray_to_runtime_obj_list(jobject["evalStack"])

    self._output_stream = Json.jarray_to_runtime_obj_list(jobject["outputStream"])
    self.output_stream_dirty()

    self._current_choices = Json.jarray_to_runtime_obj_list(jobject["currentChoices"])

    if jobject.has("currentDivertTarget"):
        var current_divert_target_path = jobject["currentDivertTarget"]
        var divert_path = InkPath.new_with_components_string(current_divert_target_path.to_string())
        self.diverted_pointer = story.pointer_at_path(divert_path)

    self.visit_counts = Json.jobject_to_int_dictionary(jobject["visitCounts"])
    self.turn_indices = Json.jobject_to_int_dictionary(jobject["turnIndices"])
    self.current_turn_index = int(jobject["turnIdx"])
    self.story_seed = int(jobject["storySeed"])
    self.previous_random = int(jobject["previousRandom"])

    var jchoice_threads = null

    if jobject.has("choiceThreads"):
        jchoice_threads = jobject["choiceThreads"]

    for c in self._current_choices:
        var found_active_thread = self.callstack.thread_with_index(c.original_thread_index)
        if found_active_thread != null:
            c.thread_at_generation = found_active_thread.copy()
        else:
            var jsaved_choice_thread = jchoice_threads[str(c.original_thread_index)]
            c.thread_at_generation = CallStack.InkThread.new_with(jsaved_choice_thread, self.story.get_ref())

# () -> void
func reset_errors():
    self._current_errors = null
    self._current_warnings = null

# (Array<InkObject>) -> void
func reset_output(objs = null):
    self._output_stream.clear()
    if objs != null: self._output_stream += objs
    self.output_stream_dirty()

# (InkObject) -> void
func push_to_output_stream(obj):
    var text = Utils.as_or_null(obj, "StringValue")
    if text:
        var list_text = self.try_splitting_head_tail_whitespace(text)
        if list_text != null:
            for text_obj in list_text:
                self.push_to_output_stream_individual(text_obj)

            self.output_stream_dirty()
            return

    self.push_to_output_stream_individual(obj)
    self.output_stream_dirty()

# (int) -> void
func pop_from_output_stream(count):
    Utils.remove_range(self.output_stream, self.output_stream.size() - count, count)
    self.output_stream_dirty()

# (StringValue) -> StringValue
func try_splitting_head_tail_whitespace(single):
    var _str = single.value

    var head_first_newline_idx = -1
    var head_last_newline_idx = -1

    var i = 0
    while (i < _str.length()):
        var c = _str[i]
        if (c == "\n"):
            if head_first_newline_idx == -1:
                head_first_newline_idx = i
            head_last_newline_idx = i
        elif c == " " || c == "\t":
            i += 1
            continue
        else:
            break
        i += 1


    var tail_last_newline_idx = -1
    var tail_first_newline_idx = -1

    i = 0
    while (i < _str.length()):
        var c = _str[i]
        if (c == "\n"):
            if tail_last_newline_idx == -1:
                tail_last_newline_idx = i
            tail_first_newline_idx = i
        elif c == ' ' || c == '\t':
            i += 1
            continue
        else:
            break
        i += 1

    if head_first_newline_idx == -1 && tail_last_newline_idx == -1:
        return null

    var list_texts = [] # Array<StringValue>
    var inner_str_start = 0
    var inner_str_end = _str.length()

    if head_first_newline_idx != -1:
        if head_first_newline_idx > 0:
            var leading_spaces = Ink.StringValue.new_with(_str.substr(0, head_first_newline_idx))
            list_texts.append(leading_spaces)

        list_texts.append(Ink.StringValue.new_with("\n"))
        inner_str_start = head_last_newline_idx + 1

    if tail_last_newline_idx != -1:
        inner_str_end = tail_first_newline_idx

    if inner_str_end > inner_str_start:
        var inner_str_text = _str.substr(inner_str_start, inner_str_end - inner_str_start)
        list_texts.append(Ink.StringValue.new(inner_str_text))

    if tail_last_newline_idx != -1 && tail_first_newline_idx > head_last_newline_idx:
        list_texts.append(Ink.StringValue.new("\n"))
        if tail_last_newline_idx < _str.length() - 1:
            var num_spaces = (_str.length() - tail_last_newline_idx) - 1
            var trailing_spaces = Ink.StringValue.new(_str.substr(tail_last_newline_idx + 1, num_spaces))
            list_texts.append(trailing_spaces)

    return list_texts

# (InkObject) -> void
func push_to_output_stream_individual(obj):
    var glue = Utils.as_or_null(obj, "Glue")
    var text = Utils.as_or_null(obj, "StringValue")

    var include_in_output = true

    if glue:
        self.trim_newlines_from_output_stream()
        include_in_output = true
    elif text:
        var function_trim_index = -1
        var curr_el = self.callstack.current_element
        if curr_el.type == PushPopType.FUNCTION:
            function_trim_index = curr_el.function_start_in_ouput_stream

        var glue_trim_index = -1
        var i = self._output_stream.size() - 1
        while (i >= 0):
            var o = self._output_stream[i]
            var c = Utils.as_or_null(o, "ControlCommand")
            var g = Utils.as_or_null(o, "Glue")

            if g:
                glue_trim_index = i
                break
            elif c && c.command_type == ControlCommand.CommandType.BEGIN_STRING:
                if i >= function_trim_index:
                    function_trim_index = -1

                break

            i -= 1

        var trim_index = -1
        if glue_trim_index != -1 && function_trim_index != -1:
            trim_index = min(function_trim_index, glue_trim_index)
        elif glue_trim_index != -1:
            trim_index = glue_trim_index
        else:
            trim_index = function_trim_index

        if trim_index != -1:
            if text.is_newline:
                include_in_output = false
            elif text.is_non_whitespace:

                if glue_trim_index > -1:
                    self.remove_existing_glue()

                if function_trim_index > -1:
                    var callstack_elements = self.callstack.elements
                    var j = callstack_elements.size() - 1
                    while j >= 0:
                        var el = callstack_elements[j]
                        if el.type == PushPopType.FUNCTION:
                            el.function_start_in_ouput_stream = -1
                        else:
                            break

                        j -= 1
        elif text.is_newline:
            if self.output_stream_ends_in_newline || !self.output_stream_contains_content:
                include_in_output = false

    if include_in_output:
        self._output_stream.append(obj)
        self.output_stream_dirty()

# () -> void
func trim_newlines_from_output_stream():
    var remove_whitespace_from = -1 # int

    var i = self._output_stream.size() - 1
    while i >= 0:
        var obj = self._output_stream[i]
        var cmd = Utils.as_or_null(obj, "ControlCommand")
        var txt = Utils.as_or_null(obj, "StringValue")

        if cmd || (txt && txt.is_non_whitespace):
            break
        elif txt && txt.is_newline:
            remove_whitespace_from = i

        i -= 1

    if remove_whitespace_from >= 0:
        i = remove_whitespace_from
        while i < _output_stream.size():
            var text = Utils.as_or_null(_output_stream[i], "StringValue")
            if text:
                self._output_stream.remove(i)
            else:
                i += 1

    self.output_stream_dirty()

# () -> void
func remove_existing_glue():
    var i = self._output_stream.size() - 1
    while (i >= 0):
        var c = self._output_stream[i]
        if Utils.is_ink_class(c, "Glue"):
            self._output_stream.remove(i)
        elif Utils.is_ink_class(c, "ControlCommand"):
            break

        i -= 1

    self.output_stream_dirty()

var output_stream_ends_in_newline setget , get_output_stream_ends_in_newline # bool
func get_output_stream_ends_in_newline():
    if self._output_stream.size() > 0:
        var i = self._output_stream.size() - 1
        while (i >= 0):
            var obj = self._output_stream[i]
            if Utils.is_ink_class(obj, "ControlCommand"):
                break
            var text = Utils.as_or_null(self._output_stream[i], "StringValue")
            if text:
                if text.is_newline:
                    return true
                elif text.is_non_whitespace:
                    break

            i -= 1

    return false

var output_stream_contains_content setget , get_output_stream_contains_content # bool
func get_output_stream_contains_content():
    for content in self._output_stream:
        if Utils.is_ink_class(content, "StringValue"):
            return true

    return false

var in_string_evaluation setget , get_in_string_evaluation # bool
func get_in_string_evaluation():
    var i = self._output_stream.size() - 1

    while (i >= 0):
        var cmd = Utils.as_or_null(self._output_stream[i], "ControlCommand")
        if cmd && cmd.command_type == ControlCommand.CommandType.BEGIN_STRING:
            return true

        i -= 1

    return false

# (InkObject) -> void
func push_evaluation_stack(obj):
    var list_value = Utils.as_or_null(obj, "ListValue")
    if list_value:
        var raw_list = list_value.value
        if raw_list.origin_names != null:
            if raw_list.origins == null: raw_list.origins = [] # Array<ListDefinition>
            raw_list.origins.clear()

            for n in raw_list.origin_names:
                var def = story.get_ref().list_definitions.try_list_get_definition(n)

                if raw_list.origins.find(def.result) < 0:
                    raw_list.origins.append(def.result)

    self.evaluation_stack.append(obj)

# () -> InkObject
func peek_evaluation_stack():
    return self.evaluation_stack.back()

# (int) -> Array<InkObject>
func pop_evaluation_stack(number_of_objects = -1):
    if number_of_objects == -1:
        return self.evaluation_stack.pop_back()

    if number_of_objects > self.evaluation_stack.size():
        Utils.throw_argument_exception("trying to pop too many objects")
        return

    var popped = Utils.get_range(self.evaluation_stack,
                                 self.evaluation_stack.size() - number_of_objects,
                                 number_of_objects)

    Utils.remove_range(self.evaluation_stack,
                       self.evaluation_stack.size() - number_of_objects, number_of_objects)
    return popped

# () -> void
func force_end():
    self.callstack.reset()

    self._current_choices.clear()

    self.current_pointer = Pointer.null()
    self.previous_pointer = Pointer.null()

    self.did_safe_exit = true

# () -> void
func trim_whitespace_from_function_end():
    assert(callstack.current_element.type == PushPopType.FUNCTION)

    var function_start_point = callstack.current_element.function_start_in_ouput_stream

    if function_start_point == -1:
        function_start_point = 0

    var i = self._output_stream.size() - 1
    while (i >= function_start_point):
        var obj = self._output_stream[i]
        var txt = Utils.as_or_null(obj, "StringValue")
        var cmd = Utils.as_or_null(obj, "ControlCommand")
        if !txt:
            i -= 1
            continue
        if cmd: break

        if txt.is_newline || txt.is_inline_whitespace:
            self._output_stream.remove(i)
            self.output_stream_dirty()
        else:
            break

        i -= 1

# (PushPopType) -> void
func pop_callstack(pop_type = null):
    if (self.callstack.current_element.type == PushPopType.FUNCTION):
        self.trim_whitespace_from_function_end()

    self.callstack.pop(pop_type)

# (InkPath, bool) -> void
func set_chosen_path(path, incrementing_turn_index):
    self._current_choices.clear()

    var new_pointer = self.story.get_ref().pointer_at_path(path)

    if !new_pointer.is_null && new_pointer.index == -1:
        new_pointer.index = 0

    self.current_pointer = new_pointer

    if incrementing_turn_index:
        self.current_turn_index += 1

# (InkContainer, [InkObject]) -> void
func start_function_evaluation_from_game(func_container, arguments):
    self.callstack.push(PushPopType.FUNCTION_EVALUATION_FROM_GAME, self.evaluation_stack.size())
    var current_element = self.callstack.current_element
    current_element.current_pointer = Pointer.start_of(func_container)

    self.pass_arguments_to_evaluation_stack(arguments)

# ([InkObject]) -> void
func pass_arguments_to_evaluation_stack(arguments):
    if arguments != null:
        var i = 0
        while (i < arguments.size()):
            if !(arguments[i] is int || arguments[i] is float || arguments[i] is String):
                Utils.throw_argument_exception(str("ink arguments when calling EvaluateFunction / ",
                                                  "ChoosePathStringWithParameters must be int, ",
                                                  "float or string"))
                return

            push_evaluation_stack(Ink.Value.create(arguments[i]))

            i += 1

# () -> bool
func try_exit_function_evaluation_from_game():
    if self.callstack.current_element.type == PushPopType.FUNCTION_EVALUATION_FROM_GAME:
        self.current_pointer = Pointer.null()
        self.did_safe_exit = true
        return true

    return false

# () -> Variant
func complete_function_evaluation_from_game():
    if self.callstack.current_element.type != PushPopType.FUNCTION_EVALUATION_FROM_GAME:
        Utils.throws_story_exception(str(
            "Expected external function evaluation to be complete. Stack trace: ",
            callstack.callstack_trace
        ))
        return null

    var original_evaluation_stack_height = self.callstack.current_element.evaluation_stack_height_when_pushed

    var returned_obj = null
    while (self.evaluation_stack.size() > original_evaluation_stack_height):
        var popped_obj = self.pop_evaluation_stack()
        if returned_obj == null:
            returned_obj = popped_obj

    self.pop_callstack(PushPopType.FUNCTION_EVALUATION_FROM_GAME)

    if returned_obj:
        if Utils.is_ink_class(returned_obj, "Void"):
            return null

        var return_val = Utils.as_or_null(returned_obj, "Value")

        if return_val.value_type == Ink.ValueType.DIVERT_TARGET:
            return return_val.value_object.to_string()

        return return_val.value_object

    return null

# (string, bool) -> void
func add_error(message, is_warning):
    if !is_warning:
        if self.current_errors == null: self.current_errors = [] # Array<string>
        self.current_errors.append(message)
    else:
        if self.current_warnings == null: self.current_warnings = [] # Array<string>
        self.current_warnings.append(message)

# () -> void
func output_stream_dirty():
    self._output_stream_text_dirty = true
    self._output_stream_tags_dirty = true

var _output_stream = null # Array<InkObject>
var _output_stream_text_dirty = true # bool
var _output_stream_tags_dirty = true # bool

var _current_choices # Array<Choice>

# ############################################################################ #
# GDScript extra methods
# ############################################################################ #

func is_class(type):
    return type == "StoryState" || .is_class(type)

func get_class():
    return "StoryState"

# ############################################################################ #

var Json = null # Eventually a pointer to InkRuntime.StaticJson

func get_json():
    var InkRuntime = Engine.get_main_loop().root.get_node("__InkRuntime")

    Utils.assert(InkRuntime != null,
                 str("Could not retrieve 'InkRuntime' singleton from the scene tree."))

    Json = InkRuntime.json
