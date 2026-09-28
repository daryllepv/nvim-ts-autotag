local api = vim.api

-- Exercise real insert-mode mappings, including cursor placement and undo.
local function marked(text)
    local lines = vim.split(text, "\n", { plain = true })
    local cursor
    for row, line in ipairs(lines) do
        local col = line:find("|", 1, true)
        if col then
            cursor = { row, col - 1 }
            lines[row] = line:sub(1, col - 1) .. line:sub(col + 1)
        end
    end
    return lines, cursor
end

describe("self-closing tags", function()
    local bufnr
    before_each(function()
        package.loaded["nvim-ts-autotag.config.plugin"] = nil
        package.loaded["nvim-ts-autotag.internal"] = nil
        require("nvim-ts-autotag.config.plugin").setup({
            opts = { enable_close = false, enable_rename = false, enable_self_close = false },
            per_filetype = {
                typescriptreact = { enable_self_close = true },
                javascript = { enable_self_close = true },
                javascriptreact = { enable_self_close = false },
                xml = { enable_self_close = true },
                html = { enable_self_close = true },
            },
        })
        bufnr = api.nvim_create_buf(true, false)
        api.nvim_set_current_buf(bufnr)
        vim.wo.virtualedit = "onemore"
    end)

    after_each(function()
        require("nvim-ts-autotag.internal").detach(bufnr)
        api.nvim_buf_delete(bufnr, { force = true })
        vim.wo.virtualedit = ""
    end)

    local function check(before, after, filetype, keys)
        local lines, cursor = marked(before)
        api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo.filetype = filetype or "typescriptreact"
        api.nvim_win_set_cursor(0, cursor)
        api.nvim_feedkeys(api.nvim_replace_termcodes("i" .. (keys or "/") .. "<Esc>", true, false, true), "xt", false)
        local expected, position = marked(after)
        assert.are.same(expected, api.nvim_buf_get_lines(bufnr, 0, -1, false))
        position[2] = math.max(0, position[2] - 1)
        assert.are.same(position, api.nvim_win_get_cursor(0))
    end

    local cases = {
        { "unfinished JSX", "const x = <div|", "const x = <div />|" },
        { "unfinished JSX with trailing space", "<div |", "<div />|" },
        {
            "unfinished component in arrow function",
            "const App = () => (\n  <component |\n);",
            "const App = () => (\n  <component />|\n);",
        },
        {
            "unfinished component in return statement",
            "function App() {\n  return (\n    <component |\n  );\n}",
            "function App() {\n  return (\n    <component />|\n  );\n}",
        },
        {
            "unfinished component attributes in parentheses",
            'const App = () => (\n  <Component x="y" |\n);',
            'const App = () => (\n  <Component x="y" />|\n);',
        },
        {
            "unfinished component without trailing space in parentheses",
            "const App = () => (<Component|);",
            "const App = () => (<Component />|);",
        },
        {
            "unfinished component with trailing space before closing parenthesis",
            "const App = () => (<component |);",
            "const App = () => (<component />|);",
        },
        { "unfinished component in array", "const xs = [<Component |];", "const xs = [<Component />|];" },
        {
            "ambiguous type parameter before comma",
            "const xs = [<Component |, <Other />];",
            "const xs = [<Component /|, <Other />];",
        },
        { "division before closing parenthesis", "const x = (value |);", "const x = (value /|);" },
        { "tag-like string in parentheses", 'const x = ("<component |");', 'const x = ("<component /|");' },
        {
            "unfinished JavaScript component in parentheses",
            "const App = () => (\n  <Component |\n);",
            "const App = () => (\n  <Component />|\n);",
            "javascript",
        },
        { "unfinished JSX with trailing whitespace", "<div \t |", "<div \t />|" },
        { "unfinished JSX attributes with trailing space", '<div x="y" |', '<div x="y" />|' },
        { "empty JSX", "<div|></div>", "<div />|" },
        { "unpaired opening tag", "<div|>", "<div />|" },
        { "attributes", '<Component x="y"|></Component>', '<Component x="y" />|' },
        { "unfinished attributes", '<Component x="y"|', '<Component x="y" />|' },
        { "expression attributes", "<Component x={a / b}|></Component>", "<Component x={a / b} />|" },
        { "member name", "<Foo.Bar|></Foo.Bar>", "<Foo.Bar />|" },
        { "unfinished member name", "<Foo.Bar|", "<Foo.Bar />|" },
        { "existing space", "<div |></div>", "<div />|" },
        { "space after cursor", "<div|  ></div>", "<div  />|" },
        { "boolean attribute", "<Component disabled|", "<Component disabled />|" },
        { "spread attribute", "<Component {...props}|", "<Component {...props} />|" },
        { "multiline attributes", '<div\n x="y"|></div>', '<div\n x="y" />|' },
        { "nested same names", "<div><div|></div></div>", "<div><div />|</div>" },
        { "nonempty", "<div|>hello</div>", "<div/|>hello</div>" },
        { "unpaired nonempty", "<div|>hello", "<div/|>hello" },
        { "whitespace content", "<div|> </div>", "<div/|> </div>" },
        { "children", "<div|><div /></div>", "<div/|><div /></div>" },
        { "attribute slash", '<div x="abc|">', '<div x="abc/|">' },
        { "unfinished string", '<div x="abc|', '<div x="abc/|' },
        { "expression slash", "<div x={a|}>", "<div x={a/|}>" },
        { "ordinary string", 'const x = "<div|"', 'const x = "<div/|"' },
        { "comparison", "const x = a < div|", "const x = a < div/|" },
        { "generic", "const x: Array<string|", "const x: Array<string/|" },
        { "already self-closed", "<div /|>", "<div //|>" },
        { "mismatched names", "<div|></span>", "<div/|></span>" },
        { "HTML excluded", "<div|></div>", "<div/|></div>", "html" },
        { "HTML template excluded", "const x = html`<div|></div>`", "const x = html`<div/|></div>`", "javascript" },
        {
            "multiline HTML injection excluded",
            "const x = html`\n<div|\n`",
            "const x = html`\n<div/|\n`",
            "javascript",
        },
        { "JavaScript JSX", "const x = <div|></div>", "const x = <div />|", "javascript" },
        { "filetype disabled", "<div|></div>", "<div/|></div>", "javascriptreact" },
        { "XML", "<div|></div>", "<div />|", "xml" },
        { "unfinished XML", "<div|", "<div />|", "xml" },
        { "unfinished XML with trailing space", "<div |", "<div />|", "xml" },
        { "unfinished XML attributes with trailing space", '<div x="y" |', '<div x="y" />|', "xml" },
        { "XML attributes", '<div x="y"|></div>', '<div x="y" />|', "xml" },
        { "unfinished XML attributes", '<div x="y"|', '<div x="y" />|', "xml" },
        { "XML content", "<div|>text</div>", "<div/|>text</div>", "xml" },
        { "XML namespace", "<foo:bar|></foo:bar>", "<foo:bar />|", "xml" },
    }
    for _, case in ipairs(cases) do
        it(case[1], function()
            check(case[2], case[3], case[4])
        end)
    end

    it("keeps existing closing-slash completion", function()
        require("nvim-ts-autotag.config.plugin").get_opts().enable_close_on_slash = true
        check("<div><|", "<div></div>|")
    end)

    it("allows a filetype to disable the global option", function()
        require("nvim-ts-autotag.config.plugin").get_opts().enable_self_close = true
        check("<div|></div>", "<div/|></div>", "javascriptreact")
    end)

    it("works alongside automatic closing and renaming", function()
        local opts = require("nvim-ts-autotag.config.plugin").get_opts()
        opts.enable_close = true
        opts.enable_rename = true
        check("<div|", "<div />|")
    end)

    it("does not enable closing-slash completion implicitly", function()
        check("<div><|", "<div></|")
    end)

    it("undoes the entire conversion together", function()
        check("<div|></div>", "<div />|")
        vim.cmd("undo")
        assert.are.same({ "<div></div>" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it("continues typing after the self-closing tag", function()
        check("<div|></div>", "<div />x|", nil, "/x")
    end)

    it("finds an unfinished tag after many unmatched opening tags", function()
        local prefix = string.rep("<div>\n", 500)
        check(prefix .. "<Component disabled |", prefix .. "<Component disabled />|")
    end)

    it("finds an unfinished tag before later malformed content", function()
        local suffix = string.rep("\n<Other", 500)
        check("<Component |" .. suffix, "<Component />|" .. suffix)
    end)

    it("preserves an ambiguous attribute before malformed content", function()
        local suffix = string.rep("\n<Other", 500)
        check("<Component disabled |" .. suffix, "<Component disabled /|" .. suffix)
    end)

    it("preserves a large nonempty element", function()
        local content = string.rep("<span />", 500)
        check("<div|>" .. content .. "</div>", "<div/|>" .. content .. "</div>")
    end)

    local page = table.concat({
        'import { WorksSection } from "./sections/works";',
        "export default function Home() {",
        "  return (",
        '    <div className="app">',
        "      <header>",
        "        <h1>Title</h1>",
        "        <p>Description</p>",
        "      </header>",
        "      <main>",
        "        <WorksSection />",
        "      </main>",
        "    </div>",
        "  );",
        "}",
    }, "\n")

    for _, sibling in ipairs({ "header", "main" }) do
        it("completes a new component before " .. sibling .. " inside app", function()
            local position = "      <" .. sibling .. ">"
            local before = page:gsub(position, "      <component |\n" .. position, 1)
            local after = page:gsub(position, "      <component />|\n" .. position, 1)
            check(before, after)
        end)
    end

    it("completes a new component before a self-closing sibling", function()
        check(
            "const App = () => (<div>\n  <component |\n  <Other />\n</div>);",
            "const App = () => (<div>\n  <component />|\n  <Other />\n</div>);"
        )
    end)

    it("completes a new component before its parent's closing tag", function()
        check(
            "const App = () => (<div>\n  <component |\n</div>);",
            "const App = () => (<div>\n  <component />|\n</div>);"
        )
    end)

    it("completes a new component inside a fragment", function()
        check("const App = () => (<>\n  <component |\n</>);", "const App = () => (<>\n  <component />|\n</>);")
    end)

    it("preserves a following sibling with the same name", function()
        check(
            "const App = () => (<div>\n  <component |\n  <component>content</component>\n</div>);",
            "const App = () => (<div>\n  <component />|\n  <component>content</component>\n</div>);"
        )
    end)

    it("does not finish a tag before its existing multiline attributes", function()
        check(
            'const App = () => (<Component |\n  value="x"\n/>);',
            'const App = () => (<Component /|\n  value="x"\n/>);'
        )
    end)

    it("does not finish a tag before its existing type arguments", function()
        check(
            "const App = () => (<Component |\n  <string> value={x}\n/>);",
            "const App = () => (<Component /|\n  <string> value={x}\n/>);"
        )
    end)
end)
