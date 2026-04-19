defmodule LincolnWeb.CoreComponents do
  @moduledoc """
  Core UI components — West World Neobrutalism design system.

  Thick borders, offset shadows, terminal fonts, high contrast.
  Built on Tailwind CSS + daisyUI.
  """
  use Phoenix.Component
  use Gettext, backend: LincolnWeb.Gettext

  alias Phoenix.HTML.Form, as: HTMLForm
  alias Phoenix.LiveView.JS

  # ============================================================================
  # Flash
  # ============================================================================

  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)
  attr(:kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup")
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")
  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap border-2 shadow-brutal-sm font-terminal",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-bold uppercase text-sm">{@title}</p>
          <p class="text-sm">{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Button
  # ============================================================================

  attr(:rest, :global, include: ~w(href navigate patch method download name value disabled))
  attr(:class, :any)
  attr(:variant, :string, values: ~w(primary))
  slot(:inner_block, required: true)

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn font-terminal", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  # ============================================================================
  # Input
  # ============================================================================

  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")
  attr(:class, :any, default: nil, doc: "the input class to use over defaults")
  attr(:error_class, :any, default: nil, doc: "the input error class to use over defaults")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)
  )

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        HTMLForm.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label font-terminal text-sm">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1 font-terminal text-sm uppercase">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || "w-full select font-terminal",
            @errors != [] && (@error_class || "select-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1 font-terminal text-sm uppercase">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea font-terminal",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1 font-terminal text-sm uppercase">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input font-terminal",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error font-terminal">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  # ============================================================================
  # Header
  # ============================================================================

  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-terminal font-bold uppercase tracking-tight">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm font-terminal text-base-content/60">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  # ============================================================================
  # Page Header — standardized across all pages
  # ============================================================================

  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:icon, :string, default: nil)
  attr(:icon_color, :string, default: "text-primary")
  slot(:actions)

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
      <div class="flex items-center gap-3">
        <div
          :if={@icon}
          class={["p-2 border-2 border-base-300 bg-base-200 shadow-brutal-sm", @icon_color]}
        >
          <.icon name={@icon} class="size-6" />
        </div>
        <div>
          <h1 class="text-xl sm:text-2xl font-black font-terminal uppercase tracking-tight">
            {@title}
          </h1>
          <p
            :if={@subtitle}
            class="text-xs font-terminal text-base-content/50 uppercase tracking-wide mt-0.5"
          >
            {@subtitle}
          </p>
        </div>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # ============================================================================
  # Table
  # ============================================================================

  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil)
  attr(:row_click, :any, default: nil)
  attr(:row_item, :any, default: &Function.identity/1)

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action)

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra font-terminal text-sm">
      <thead>
        <tr class="border-b-2 border-base-300">
          <th :for={col <- @col} class="font-terminal uppercase text-xs tracking-wide">
            {col[:label]}
          </th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="border-b border-base-300/50">
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  # ============================================================================
  # List
  # ============================================================================

  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-terminal font-bold text-sm">{item.title}</div>
          <div class="text-sm">{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  # ============================================================================
  # Icon
  # ============================================================================

  attr(:name, :string, required: true)
  attr(:class, :any, default: "size-4")

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  # ============================================================================
  # Card — neobrutalist with variant borders
  # ============================================================================

  attr(:class, :string, default: nil)

  attr(:variant, :atom,
    default: :default,
    values: [:default, :primary, :secondary, :accent, :warning, :error, :info]
  )

  slot(:header)
  slot(:inner_block, required: true)

  def card(assigns) do
    ~H"""
    <div class={[
      "bg-base-200 border-2 shadow-brutal-sm",
      variant_border(@variant),
      @class
    ]}>
      <div
        :if={@header != []}
        class={[
          "px-4 py-2.5 border-b-2 bg-base-300/50 font-terminal text-sm uppercase tracking-wide flex items-center justify-between",
          variant_border_b(@variant)
        ]}
      >
        {render_slot(@header)}
      </div>
      <div class="p-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp variant_border(:default), do: "border-base-300"
  defp variant_border(:primary), do: "border-primary/40"
  defp variant_border(:secondary), do: "border-secondary/40"
  defp variant_border(:accent), do: "border-accent/40"
  defp variant_border(:warning), do: "border-warning/40"
  defp variant_border(:error), do: "border-error/40"
  defp variant_border(:info), do: "border-info/40"

  defp variant_border_b(:default), do: "border-base-300"
  defp variant_border_b(:primary), do: "border-primary/30"
  defp variant_border_b(:secondary), do: "border-secondary/30"
  defp variant_border_b(:accent), do: "border-accent/30"
  defp variant_border_b(:warning), do: "border-warning/30"
  defp variant_border_b(:error), do: "border-error/30"
  defp variant_border_b(:info), do: "border-info/30"

  # ============================================================================
  # Stat Card — neobrutalist dashboard stats
  # ============================================================================

  attr(:title, :string, required: true)
  attr(:value, :string, required: true)
  attr(:icon, :string, default: nil)
  attr(:description, :string, default: nil)
  attr(:class, :string, default: nil)

  def stat_card(assigns) do
    ~H"""
    <div class={["bg-base-200 border-2 border-base-300 p-4 shadow-brutal-sm", @class]}>
      <div class="flex items-start justify-between">
        <div>
          <p class="text-[10px] font-terminal uppercase tracking-widest text-base-content/50">
            {@title}
          </p>
          <p class="text-2xl font-bold font-terminal mt-1">{@value}</p>
          <p :if={@description} class="text-xs font-terminal text-base-content/40 mt-1">
            {@description}
          </p>
        </div>
        <div :if={@icon} class="text-primary/50">
          <.icon name={@icon} class="size-6" />
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Data Card — dashboard panels with header, icon, optional view-all link
  # ============================================================================

  attr(:title, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:icon_color, :string, default: "text-primary")
  attr(:border_color, :string, default: "border-primary/40")
  attr(:view_all_path, :string, default: nil)
  attr(:max_height, :string, default: "max-h-80")
  slot(:inner_block, required: true)

  def data_card(assigns) do
    ~H"""
    <div class={["bg-base-200 border-2 shadow-brutal-sm", @border_color]}>
      <div class={[
        "flex items-center justify-between px-4 py-2.5 border-b-2 bg-base-300/50",
        @border_color
      ]}>
        <h2 class="text-sm font-terminal font-bold uppercase tracking-wide flex items-center gap-2">
          <.icon name={@icon} class={["size-4", @icon_color]} /> {@title}
        </h2>
        <.link
          :if={@view_all_path}
          navigate={@view_all_path}
          class="text-xs font-terminal text-base-content/40 hover:text-primary transition-colors uppercase tracking-wide"
        >
          View All <.icon name="hero-arrow-right" class="size-3 inline" />
        </.link>
      </div>
      <div class={["p-4 overflow-y-auto", @max_height]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ============================================================================
  # Empty State
  # ============================================================================

  attr(:icon, :string, default: "hero-inbox")
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:action)

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-10 text-center">
      <div class="text-base-content/20 mb-3">
        <.icon name={@icon} class="size-10" />
      </div>
      <h3 class="text-sm font-terminal font-bold uppercase text-base-content/50">{@title}</h3>
      <p :if={@description} class="text-xs font-terminal text-base-content/40 mt-1 max-w-sm">
        {@description}
      </p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  # ============================================================================
  # Section Header
  # ============================================================================

  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  slot(:actions)

  def section_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4 pb-2 border-b-2 border-base-300">
      <div>
        <h2 class="text-base font-terminal font-bold uppercase tracking-tight">{@title}</h2>
        <p :if={@subtitle} class="text-xs font-terminal text-base-content/50 mt-0.5">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # ============================================================================
  # Status Indicator — replaces 3 different implementations
  # ============================================================================

  attr(:status, :atom, required: true, values: [:online, :offline, :warning, :error, :idle])
  attr(:label, :string, default: nil)
  attr(:pulse, :boolean, default: false)
  attr(:size, :atom, default: :md, values: [:sm, :md, :lg])

  def status_indicator(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <span class={[
        "status-dot",
        status_dot_class(@status),
        @pulse && "neural-pulse",
        status_size(@size)
      ]} />
      <span :if={@label} class="text-xs font-terminal uppercase">{@label}</span>
    </span>
    """
  end

  defp status_dot_class(:online), do: "status-dot-online"
  defp status_dot_class(:offline), do: "status-dot-offline"
  defp status_dot_class(:warning), do: "status-dot-warning"
  defp status_dot_class(:error), do: "status-dot-error"
  defp status_dot_class(:idle), do: "status-dot-idle"

  defp status_size(:sm), do: "!w-1.5 !h-1.5"
  defp status_size(:md), do: nil
  defp status_size(:lg), do: "!w-3 !h-3"

  # ============================================================================
  # Filter Tabs — standardized filter UI
  # ============================================================================

  attr(:options, :list, required: true, doc: "list of {value, label} tuples")
  attr(:active, :string, required: true)
  attr(:event, :string, default: "filter")

  def filter_tabs(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <button
        :for={{value, label} <- @options}
        phx-click={@event}
        phx-value-filter={value}
        class={[
          "px-3 py-1.5 text-xs font-terminal font-bold uppercase border-2 transition-all cursor-pointer",
          if(value == @active,
            do: "bg-primary text-primary-content border-primary shadow-brutal-sm",
            else:
              "bg-base-200 text-base-content/60 border-base-300 hover:border-base-content/30 hover:text-base-content"
          )
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  # ============================================================================
  # Pagination
  # ============================================================================

  attr(:end_of_list?, :boolean, default: false)
  attr(:loading?, :boolean, default: false)

  def load_more(assigns) do
    ~H"""
    <div :if={!@end_of_list?} class="flex justify-center mt-4 py-2">
      <button
        :if={!@loading?}
        phx-click="load-more"
        class="btn btn-ghost btn-sm font-terminal uppercase tracking-wide text-xs border-2 border-base-300 hover:border-primary"
      >
        <.icon name="hero-arrow-down" class="size-3" /> Load More
      </button>
      <span :if={@loading?} class="loading loading-spinner loading-sm text-primary"></span>
    </div>
    <div :if={@end_of_list?} class="flex justify-center mt-4 py-2">
      <span class="text-xs font-terminal text-base-content/30 uppercase">End of list</span>
    </div>
    """
  end

  # ============================================================================
  # Badge — neobrutalist with thick borders
  # ============================================================================

  attr(:type, :atom,
    default: :default,
    values: [:default, :primary, :secondary, :success, :warning, :error, :info, :accent]
  )

  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 text-[10px] font-terminal font-bold uppercase border tracking-wide",
      badge_class(@type),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_class(:default), do: "bg-base-300 text-base-content border-base-content/20"
  defp badge_class(:primary), do: "bg-primary/15 text-primary border-primary/30"
  defp badge_class(:secondary), do: "bg-secondary/15 text-secondary border-secondary/30"
  defp badge_class(:success), do: "bg-success/15 text-success border-success/30"
  defp badge_class(:warning), do: "bg-warning/15 text-warning border-warning/30"
  defp badge_class(:error), do: "bg-error/15 text-error border-error/30"
  defp badge_class(:info), do: "bg-info/15 text-info border-info/30"
  defp badge_class(:accent), do: "bg-accent/15 text-accent border-accent/30"

  # ============================================================================
  # Skeleton
  # ============================================================================

  attr(:class, :string, default: nil)
  attr(:type, :atom, default: :text, values: [:text, :circle, :card])

  def skeleton(assigns) do
    ~H"""
    <div class={["animate-pulse bg-base-300", skeleton_class(@type), @class]} />
    """
  end

  defp skeleton_class(:text), do: "h-4 w-full"
  defp skeleton_class(:circle), do: "h-10 w-10 rounded-full"
  defp skeleton_class(:card), do: "h-24 w-full"

  # ============================================================================
  # JS Commands
  # ============================================================================

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 150,
      transition:
        {"transition-all ease-out duration-150", "opacity-0 translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 100,
      transition:
        {"transition-all ease-in duration-100", "opacity-100 translate-y-0",
         "opacity-0 translate-y-2"}
    )
  end

  # ============================================================================
  # Gettext helpers
  # ============================================================================

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(LincolnWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LincolnWeb.Gettext, "errors", msg, opts)
    end
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
