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
# Imports
# ############################################################################ #

var PushPopType = preload("res://addons/inkgd/runtime/push_pop.gd").PushPopType
var Pointer = load("res://addons/inkgd/runtime/pointer.gd")
var Ink = load("res://addons/inkgd/runtime/value.gd")

# ############################################################################ #

class Element extends "res://addons/inkgd/runtime/ink_base.gd":
    # ######################################################################## #
    # Imports
    # ######################################################################## #

    var Pointer = load("res://addons/inkgd/runtime/pointer.gd")

    # ######################################################################## #

    var current_pointer = Pointer.null() # Pointer

    var in_expression_evaluation = false # bool
    var temporary_variables = null # Dictionary<String, InkObject>
    var type = 0 # PushPopType
    var evaluation_stack_height_when_pushed = 0 # int
    var function_start_in_ouput_stream = 0 # int

    # (PushPopType, Pointer, bool) -> InkElement
    func _init(type, pointer, in_expression_evaluation = false):
        self.current_pointer = pointer.duplicate()
        self.in_expression_evaluation = in_expression_evaluation
        self.temporary_variables = {}
        self.type = type

    # () -> InkElement
    func copy():
        var copy = Element.new(self.type, self.current_pointer, self.in_expression_evaluation)
        copy.temporary_variables = self.temporary_variables.duplicate()
        copy.evaluation_stack_height_when_pushed = evaluation_stack_height_when_pushed
        copy.function_start_in_ouput_stream = function_start_in_ouput_stream
        return copy

    # ######################################################################## #
    # GDScript extra methods
    # ######################################################################## #

    func is_class(type):
        return type == "CallStack.Element" || .is_class(type)

    func get_class():
        return "CallStack.Element"

class InkThread extends "res://addons/inkgd/runtime/ink_base.gd":
    # ######################################################################## #
    # Imports
    # ######################################################################## #

    var Pointer = load("res://addons/inkgd/runtime/pointer.gd")
    var InkPath = load("res://addons/inkgd/runtime/ink_path.gd")

    # ######################################################################## #

    var callstack = null # Array<Element>
    var thread_index = 0 # int
    var previous_pointer = Pointer.null() # Pointer

    func _init():
        get_json()
        callstack = []

    # Dictionary<string, object>, Story
    func _init_with(jthread_obj, story_context):
        thread_index = int(jthread_obj["threadIndex"])
        var jthread_callstack = jthread_obj["callstack"]

        for jel_tok in jthread_callstack:
            var jelement_obj = jel_tok
            var push_pop_type = int(jelement_obj["type"])

            var pointer = Pointer.null()
            var current_container_path_str = null
            var current_container_path_str_token = null

            if jelement_obj.has("cPath"):
                current_container_path_str_token = jelement_obj["cPath"]
                current_container_path_str = str(current_container_path_str_token)

                var thread_pointer_result = story_context.content_at_path(InkPath.new_with_components_string(current_container_path_str))
                pointer.container = thread_pointer_result.container
                pointer.index = int(jelement_obj["idx"])

                if thread_pointer_result.obj == null:
                    Utils.throw_exception(
                        "When loading state, internal story location couldn't be found: " +
                        current_container_path_str +
                        ". Has the story changed since this save data was created?"
                    )
                    return
                elif thread_pointer_result.approximate:
                    story_context.warning(
                        "When loading state, exact internal story location couldn't be found: '" +
                        current_container_path_str + "', so it was approximated to '" +
                        pointer.container.path.to_string() +
                        "' to recover. Has the story changed since this save data was created?"
                    )

            var in_expression_evaluation = bool(jelement_obj["exp"])
            var el = Element.new(push_pop_type, pointer, in_expression_evaluation)
            var jobj_temps = jelement_obj["temp"] # Dictionary<string, object>
            el.temporary_variables = Json.jobject_to_dictionary_runtime_objs(jobj_temps)

            callstack.append(el)

        var prev_content_obj_path
        if jthread_obj.has("previousContentObject"):
            prev_content_obj_path = str(jthread_obj["previousContentObject"])
            var prev_path = InkPath.new_with_components_string(prev_content_obj_path)
            self.previous_pointer = story_context.pointer_at_path(prev_path)

    # () -> InkThread
    func copy():
        var copy = InkThread.new()
        copy.thread_index = self.thread_index
        for e in callstack:
            copy.callstack.append(e.copy())
        copy.previous_pointer = self.previous_pointer.duplicate()
        return copy

    # () -> # Dictionary<String, object>
    var json_token setget , get_json_token
    func get_json_token():
        var thread_jobj = {} # Dictionary<string, object>
        var jthread_callstack = [] # Array<Object>

        for el in callstack:
            var jobj = {} # Dictionary<string, object>
            if !el.current_pointer.is_null:
                jobj["cPath"] = el.current_pointer.container.path.components_string
                jobj["idx"] = el.current_pointer.index

            jobj["exp"] = el.in_expression_evaluation
            jobj["type"] = int(el.type)
            jobj["temp"] = Json.dictionary_runtime_objs_to_jobject(el.temporary_variables)
            jthread_callstack.append(jobj)

        thread_jobj["callstack"] = jthread_callstack
        thread_jobj["threadIndex"] = thread_index

        if !self.previous_pointer.is_null:
            thread_jobj["previousContentObject"] = self.previous_pointer.resolve().path.to_string()

        return thread_jobj

    # ######################################################################## #
    # GDScript extra methods
    # ######################################################################## #

    func is_class(type):
        return type == "CallStack.InkThread" || .is_class(type)

    func get_class():
        return "CallStack.InkThread"

    # ######################################################################## #

    static func new_with(jthread_obj, story_context):
        var thread = InkThread.new()
        thread._init_with(jthread_obj, story_context)
        return thread

    # ######################################################################## #

    var Json = null # Eventually a pointer to InkRuntime.StaticJson

    func get_json():
        var InkRuntime = Engine.get_main_loop().root.get_node("__InkRuntime")

        Utils.assert(InkRuntime != null,
                     str("Could not retrieve 'InkRuntime' singleton from the scene tree."))

        Json = InkRuntime.json

# () -> Array<InkElement>
var elements setget , get_elements
func get_elements():
    return self.callstack

# () -> int
var depth setget , get_depth
func get_depth():
    return self.elements.size()

# () -> InkElement
var current_element setget , get_current_element
func get_current_element():
    var thread = self._threads.back()
    var cs = thread.callstack
    return cs.back()

# () -> int
var current_element_index setget , get_current_element_index
func get_current_element_index():
    return self.callstack.size() - 1

# () -> InkThread
# (InkThread) -> void
var current_thread setget set_current_thread, get_current_thread
func get_current_thread():
    return self._threads.back()

func set_current_thread(value):
    Utils.assert(_threads.size() == 1,
                 "Shouldn't be directly setting the current thread when we have a stack of them")
    self._threads.clear()
    self._threads.append(value)

# () -> bool
var can_pop setget , get_can_pop
func get_can_pop():
    return self.callstack.size() > 1

# (InkStory | CallStack) -> CallStack
func _init(story_context_or_to_copy):
    get_json() # Retrieve pointer to global Json Object

    if story_context_or_to_copy.is_class("Story"):
        var story_context = story_context_or_to_copy
        _start_of_root = Pointer.start_of(story_context.root_content_container)
        reset()
    elif story_context_or_to_copy.is_class("CallStack"):
        var to_copy = story_context_or_to_copy
        self._threads = []
        for other_thread in to_copy._threads:
            self._threads.append(other_thread.copy())
        self._start_of_root = to_copy._start_of_root

# () -> void
func reset():
    self._threads = []
    self._threads.append(InkThread.new())
    self._threads[0].callstack.append(Element.new(PushPopType.TUNNEL, self._start_of_root))

# (Dictionary<string, object>, InkStory) -> void
func set_json_token(jobject, story_context):
    self._threads.clear()
    var jthreads = jobject["threads"]

    for jthread_tok in jthreads:
        var jthread_obj = jthread_tok
        var thread = InkThread.new_with(jthread_obj, story_context)
        self._threads.append(thread)

    self._thread_counter = int(jobject["threadCounter"])
    self._start_of_root = Pointer.start_of(story_context.root_content_container)


# () -> Dictionary<string, object>
func get_json_token():
    var jobject = {} # Dictionary<string, object>
    var jthreads = [] # Array<object>

    for thread in self._threads:
        jthreads.append(thread.json_token)

    jobject["threads"] = jthreads
    jobject["threadCounter"] = self._thread_counter

    return jobject

# () -> void
func push_thread():
    var new_thread = self.current_thread.copy()
    self._thread_counter += 1
    new_thread.thread_index = self._thread_counter
    self._threads.append(new_thread)

# () -> void
func fork_thread():
    var forked_thread = self.current_thread.copy()
    self._thread_counter += 1
    forked_thread.thread_index = self._thread_counter
    return forked_thread

# () -> void
func pop_thread():
    if self.can_pop_thread:
        self._threads.erase(self.current_thread)
    else:
        Utils.throw_exception("Can't pop thread")

# () -> bool
var can_pop_thread setget , get_can_pop_thread
func get_can_pop_thread():
    return _threads.size() > 1 && !self.element_is_evaluate_from_game

# () -> bool
var element_is_evaluate_from_game setget , get_element_is_evaluate_from_game
func get_element_is_evaluate_from_game():
    return self.current_element.type == PushPopType.FUNCTION_EVALUATION_FROM_GAME

# (PushPopType, int, int) -> void
func push(type, external_evaluation_stack_height = 0, output_stream_length_with_pushed = 0):
    var element = Element.new(type, self.current_element.current_pointer, false)

    element.evaluation_stack_height_when_pushed = external_evaluation_stack_height
    element.function_start_in_ouput_stream = output_stream_length_with_pushed

    self.callstack.append(element)

# (PushPopType | null) -> void
func can_pop_type(type = null): # MARK: Renamed Method
    if !self.can_pop:
        return false

    if type == null:
        return true

    return self.current_element.type == type

# (PushPopType | null) -> void
func pop(type = null):
    if can_pop_type(type):
        self.callstack.pop_back()
        return
    else:
        Utils.throw_exception("Mismatched push/pop in Callstack")

# (String, int) -> InkObject
func get_temporary_variable_with_name(name, context_index = -1):
    if context_index == -1:
        context_index = self.current_element_index + 1

    var var_value = null

    var context_element = self.callstack[context_index - 1]

    if context_element.temporary_variables.has(name):
        var_value = context_element.temporary_variables[name]
        return var_value
    else:
        return null

# (String, InkObject, bool, int) -> void
func set_temporary_variable(name, value, declare_new, context_index = -1):
    if context_index == -1:
        context_index = self.current_element_index + 1

    var context_element = self.callstack[context_index - 1]

    if !declare_new && !context_element.temporary_variables.has(name):
        Utils.throw_story_exception("Could not find temporary variable to set: " + name)
        return

    if context_element.temporary_variables.has(name):
        var old_value = context_element.temporary_variables[name]
        Ink.ListValue.retain_list_origins_for_assignment(old_value, value)

    context_element.temporary_variables[name] = value


# (String) -> int
func context_for_variable_named(name):
    if self.current_element.temporary_variables.has(name):
        return self.current_element_index + 1
    else:
        return 0

# (int) -> InkThread | null
func thread_with_index(index):
    for thread in self._threads:
        if thread.thread_index == index:
            return thread

    return null

var callstack setget , get_callstack
func get_callstack():
    return self.current_thread.callstack

var callstack_trace setget , get_callstack_trace
func get_callstack_trace():
    var sb = ""
    var t = 0
    while t < _threads.size():
        var thread = _threads[t]
        var is_current = (t == _threads.size() - 1)
        sb += str("=== THREAD ", str(t + 1), "/", str(_threads.size()), " ",
                 ("(current) " if is_current else "" ), "===\n")

        var i = 0
        while i < _threads.callstack.size():
            if thread.callstack[i].type == PushPopType.FUNCTION:
                sb += "  [FUNCTION] "
            else:
                sb += "  [TUNNEL] "

            var pointer = thread.callstack[i].current_pointer
            if !pointer.is_null:
                sb += "<SOMEWHERE IN "
                sb += pointer.container.path.to_string()
                sb += "\n>"

            i += 1
        t += 1

    return sb

var _threads = null # Array<InkThread>
var _thread_counter = 0 # int
var _start_of_root = Pointer.null() # Pointer

# ############################################################################ #
# GDScript extra methods
# ############################################################################ #

func is_class(type):
    return type == "CallStack" || .is_class(type)

func get_class():
    return "CallStack"

# ############################################################################ #

var Json = null # Eventually a pointer to InkRuntime.StaticJson

func get_json():
    var InkRuntime = Engine.get_main_loop().root.get_node("__InkRuntime")

    Utils.assert(InkRuntime != null,
                 str("Could not retrieve 'InkRuntime' singleton from the scene tree."))

    Json = InkRuntime.json
