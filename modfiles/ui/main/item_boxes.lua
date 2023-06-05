-- ** LOCAL UTIL **
local function add_recipe(player, context, type, item_proto)
    if context.floor.level > 1 then
        local message = {"fp.error_recipe_wrong_floor", {"fp.pu_" .. type, 1}}
        util.messages.raise(player, "error", message, 1)
    else
        local production_type = (type == "byproduct") and "consume" or "produce"
        util.raise.open_dialog(player, {dialog="recipe",
            modal_data={category_id=item_proto.category_id, product_id=item_proto.id,
            floor_id=context.floor.id, production_type=production_type}})
    end
end

local function build_item_box(player, category, column_count)
    local item_boxes_elements = util.globals.main_elements(player).item_boxes

    local window_frame = item_boxes_elements.horizontal_flow.add{type="frame", direction="vertical",
        style="inside_shallow_frame"}
    window_frame.style.top_padding = 6
    window_frame.style.bottom_padding = MAGIC_NUMBERS.frame_spacing

    local title_flow = window_frame.add{type="flow", direction="horizontal"}
    title_flow.style.vertical_align = "center"

    local label = title_flow.add{type="label", caption={"fp.pu_" .. category, 2}, style="caption_label"}
    label.style.left_padding = MAGIC_NUMBERS.frame_spacing
    label.style.bottom_margin = 4

    if category == "ingredient" then
        local button_combinator = title_flow.add{type="sprite-button", sprite="item/constant-combinator",
            tooltip={"fp.ingredients_to_combinator_tt"}, tags={mod="fp", on_gui_click="ingredients_to_combinator"},
            visible=false, mouse_button_filter={"left"}}
        button_combinator.style.size = 24
        button_combinator.style.padding = -2
        button_combinator.style.left_margin = 4
        item_boxes_elements["ingredient_combinator_button"] = button_combinator
    end

    local scroll_pane = window_frame.add{type="scroll-pane", style="fp_scroll-pane_slot_table"}
    scroll_pane.style.maximal_height = MAGIC_NUMBERS.item_box_max_rows * MAGIC_NUMBERS.item_button_size
    scroll_pane.style.horizontally_stretchable = false
    scroll_pane.style.vertically_stretchable = false

    local item_frame = scroll_pane.add{type="frame", style="slot_button_deep_frame"}
    item_frame.style.width = column_count * MAGIC_NUMBERS.item_button_size

    local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}
    item_boxes_elements[category .. "_item_table"] = table_items
end

local function refresh_item_box(player, items, category, subfactory, shows_floor_items)
    local ui_state = util.globals.ui_state(player)
    local item_boxes_elements = ui_state.main_elements.item_boxes

    local table_items = item_boxes_elements[category .. "_item_table"]
    table_items.clear()

    if not subfactory or not subfactory.valid then
        item_boxes_elements["ingredient_combinator_button"].visible = false
        return 0
    end

    local table_item_count = 0
    local metadata = view_state.generate_metadata(player, subfactory)
    local default_style = (category == "byproduct") and "flib_slot_button_red" or "flib_slot_button_default"

    local action = (shows_floor_items) and ("act_on_floor_item") or ("act_on_top_level_" .. category)
    local tutorial_tt = (util.globals.preferences(player).tutorial_mode)
        and data_util.generate_tutorial_tooltip(action, nil, player) or nil

    for _, item in ipairs(items) do
        local required_amount = (not shows_floor_items and category == "product") and Item.required_amount(item) or nil
        local amount, number_tooltip = view_state.process_item(metadata, item, required_amount, nil)
        if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error

        local style = default_style
        local satisfaction_line = ""  ---@type LocalisedString
        if not shows_floor_items and category == "product" and amount ~= nil and amount ~= "0" then
            local satisfied_percentage = (item.amount / required_amount) * 100
            local percentage_string = util.format.number(satisfied_percentage, 3)
            satisfaction_line = {"", "\n", {"fp.bold_label", (percentage_string .. "%")}, " ", {"fp.satisfied"}}

            if satisfied_percentage <= 0 then style = "flib_slot_button_red"
            elseif satisfied_percentage < 100 then style = "flib_slot_button_yellow"
            else style = "flib_slot_button_green" end
        end

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local name_line, tooltip, enabled = nil, nil, true
        if item.proto.type == "entity" then  -- only relevant to ingredients
            name_line = {"fp.tt_title_with_note", item.proto.localised_name, {"fp.raw_ore"}}
            tooltip = {"", name_line, number_line, satisfaction_line}
            style = "flib_slot_button_transparent"
            enabled = false
        else
            name_line = {"fp.tt_title", item.proto.localised_name}
            tooltip = {"", name_line, number_line, satisfaction_line, tutorial_tt}
        end

        table_items.add{type="sprite-button", tooltip=tooltip, number=amount, style=style, sprite=item.proto.sprite,
            tags={mod="fp", on_gui_click=action, category=category, item_id=item.id}, enabled=enabled,
            mouse_button_filter={"left-and-right"}}
        table_item_count = table_item_count + 1

        ::skip_item::  -- goto for fun, wooohoo
    end

    if category == "product" and not shows_floor_items then  -- meaning allow the user to add items of this type
        table_items.add{type="sprite-button", enabled=(not ui_state.flags.archive_open),
            tags={mod="fp", on_gui_click="add_top_level_item", category=category}, sprite="utility/add",
            tooltip={"", {"fp.add"}, " ", {"fp.pl_" .. category, 1}, "\n", {"fp.shift_to_paste"}},
            style="fp_sprite-button_inset_add_slot", mouse_button_filter={"left"}}
        table_item_count = table_item_count + 1
    end

    if category == "ingredient" then
        item_boxes_elements["ingredient_combinator_button"].visible = (table_item_count > 0)
    end

    local table_rows_required = math.ceil(table_item_count / table_items.column_count)
    return table_rows_required
end


local function handle_item_add(player, tags, event)
    local context = util.globals.context(player)

    if event.shift then  -- paste
        -- Use a fake item to paste on top of
        local class = tags.category:gsub("^%l", string.upper)
        local fake_item = {proto={name=""}, parent=context.subfactory, class=class}
        util.clipboard.paste(player, fake_item)
    else
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category=tags.category}})
    end
end

local function handle_item_button_click(player, tags, action)
    local player_table = util.globals.player_table(player)
    local context = player_table.ui_state.context
    local floor_items_active = (player_table.preferences.show_floor_items and context.floor.level > 1)

    local class = (tags.category:gsub("^%l", string.upper))
    local item = (floor_items_active) and Line.get(context.floor.origin_line, class, tags.item_id)
        or Subfactory.get(context.subfactory, class, tags.item_id)

    if action == "add_recipe" then
        add_recipe(player, context, tags.category, item.proto)

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})

    elseif action == "copy" then
        util.clipboard.copy(player, item)

    elseif action == "paste" then
        util.clipboard.paste(player, item)

    elseif action == "delete" then
        Subfactory.remove(context.subfactory, item)
        solver.update(player, context.subfactory)
        util.raise.refresh(player, "all", nil)  -- make sure product icons are updated

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale")
        util.raise.refresh(player, "subfactory", nil)

        local modal_data = {
            title = {"fp.options_item_title", {"fp.pl_ingredient", 1}},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler_name = "scale_subfactory_by_ingredient_amount",
            item_id = item.id,
            fields = {
                {
                    type = "numeric_textfield",
                    name = "item_amount",
                    caption = {"fp.options_item_amount"},
                    tooltip = {"fp.options_subfactory_ingredient_amount_tt"},
                    text = item.amount,
                    width = 140,
                    focus = true
                }
            }
        }
        util.raise.open_dialog(player, {dialog="options", modal_data=modal_data})

    elseif action == "put_into_cursor" then
        local amount = (not floor_items_active and tags.category == "product")
            and Item.required_amount(item) or item.amount
        util.cursor.add_to_item_combinator(player, item.proto, amount)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, item.proto.type, item.proto.name)
    end
end


local function put_ingredients_into_cursor(player, _, _)
    local context = util.globals.context(player)
    local floor = context.floor
    local show_floor_items = util.globals.preferences(player).show_floor_items
    local container = (show_floor_items and floor.level > 1) and floor.origin_line or context.subfactory

    local ingredients = {}
    for _, ingredient in pairs(_G[container.class].get_all(container, "Ingredient")) do
        if ingredient.proto.type == "item" then ingredients[ingredient.proto.name] = ingredient.amount end
    end

    local success = util.cursor.set_item_combinator(player, ingredients)
    if success then main_dialog.toggle(player) end
end


local function scale_subfactory_by_ingredient_amount(player, options, action)
    if action == "submit" then
        local ui_state = util.globals.ui_state(player)
        local subfactory = ui_state.context.subfactory
        local item = Subfactory.get(subfactory, "Ingredient", ui_state.modal_data.item_id)

        if options.item_amount then
            -- The division is not pre-calculated to avoid precision errors in some cases
            local current_amount, target_amount = item.amount, options.item_amount
            for _, product in pairs(Subfactory.get_all(subfactory, "Product")) do
                local requirement = product.required_amount
                requirement.amount = requirement.amount * target_amount / current_amount
            end
        end

        solver.update(player, subfactory)
        util.raise.refresh(player, "subfactory", nil)
    end
end


local function refresh_item_boxes(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local context = player_table.ui_state.context
    local subfactory = context.subfactory
    local floor = context.floor

    -- This is all kinds of stupid, but the mob wishes the feature to exist
    local function refresh(parent, class, shows_floor_items)
        local items = (parent) and _G[parent.class].get_in_order(parent, class) or {}
        return refresh_item_box(player, items, class:lower(), subfactory, shows_floor_items)
    end

    local prow_count, brow_count, irow_count = 0, 0, 0
    if player_table.preferences.show_floor_items and floor and floor.level > 1 then
        local line = floor.origin_line
        prow_count = refresh(line, "Product", true)
        brow_count = refresh(line, "Byproduct", true)
        irow_count = refresh(line, "Ingredient", true)
    else
        prow_count = refresh(subfactory, "Product", false)
        brow_count = refresh(subfactory, "Byproduct", false)
        irow_count = refresh(subfactory, "Ingredient", false)
    end

    local maxrow_count = math.max(prow_count, math.max(brow_count, irow_count))
    local actual_row_count = math.min(math.max(maxrow_count, 1), MAGIC_NUMBERS.item_box_max_rows)
    local item_table_height = actual_row_count * MAGIC_NUMBERS.item_button_size

    -- set the heights for both the visible frame and the scroll pane containing it
    local item_boxes_elements = player_table.ui_state.main_elements.item_boxes
    item_boxes_elements.product_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.product_item_table.parent.parent.style.minimal_height = item_table_height
    item_boxes_elements.byproduct_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.byproduct_item_table.parent.parent.style.minimal_height = item_table_height
    item_boxes_elements.ingredient_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.ingredient_item_table.parent.parent.style.minimal_height = item_table_height
end

local function build_item_boxes(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.item_boxes = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_horizontal = parent_flow.add{type="flow", direction="horizontal"}
    flow_horizontal.style.horizontal_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.item_boxes["horizontal_flow"] = flow_horizontal

    local products_per_row = util.globals.settings(player).products_per_row
    build_item_box(player, "product", products_per_row)
    build_item_box(player, "byproduct", products_per_row)
    build_item_box(player, "ingredient", products_per_row*2)

    refresh_item_boxes(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "add_top_level_item",
            handler = handle_item_add
        },
        {
            name = "act_on_top_level_product",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false}},
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_byproduct",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false, matrix_active=true}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_ingredient",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false}},
                specify_amount = {"right", {archive_open=false}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_item",
            modifier_actions = {
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "ingredients_to_combinator",
            timeout = 20,
            handler = put_ingredients_into_cursor
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_item_boxes(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {item_boxes=true, production=true, subfactory=true, all=true}
        if triggers[event.trigger] then refresh_item_boxes(player) end
    end)
}

listeners.global = {
    scale_subfactory_by_ingredient_amount = scale_subfactory_by_ingredient_amount
}

return { listeners }
