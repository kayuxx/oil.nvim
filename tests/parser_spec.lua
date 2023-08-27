require("plenary.async").tests.add_to_env()
local cache = require("oil.cache")
local constants = require("oil.constants")
local parser = require("oil.mutator.parser")
local test_adapter = require("oil.adapters.test")
local test_util = require("tests.test_util")
local util = require("oil.util")
local view = require("oil.view")

local FIELD_ID = constants.FIELD_ID
local FIELD_META = constants.FIELD_META

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
end

describe("parser", function()
  after_each(function()
    test_adapter.test_clear()
    cache.clear_everything()
    test_util.reset_editor()
  end)

  it("detects new files", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "a.txt",
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({ { entry_type = "file", name = "a.txt", type = "new" } }, diffs)
  end)

  it("detects new directories", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "foo/",
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({ { entry_type = "directory", name = "foo", type = "new" } }, diffs)
  end)

  it("detects new links", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "a.txt -> b.txt",
    })
    local diffs = parser.parse(bufnr)
    assert.are.same(
      { { entry_type = "link", name = "a.txt", type = "new", link = "b.txt" } },
      diffs
    )
  end)

  it("detects deleted files", function()
    local file = test_adapter.test_set("/foo/a.txt", "file")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = "a.txt", type = "delete", id = file[FIELD_ID] },
    }, diffs)
  end)

  it("detects deleted directories", function()
    local dir = test_adapter.test_set("/foo/bar", "directory")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = "bar", type = "delete", id = dir[FIELD_ID] },
    }, diffs)
  end)

  it("detects deleted links", function()
    local file = test_adapter.test_set("/foo/a.txt", "link")
    file[FIELD_META] = { link = "b.txt" }
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = "a.txt", type = "delete", id = file[FIELD_ID] },
    }, diffs)
  end)

  it("ignores empty lines", function()
    local file = test_adapter.test_set("/foo/a.txt", "file")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    local cols = view.format_entry_cols(file, {}, {}, test_adapter)
    local lines = util.render_table({ cols }, {})
    table.insert(lines, "")
    table.insert(lines, "     ")
    set_lines(bufnr, lines)
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)

  it("errors on missing filename", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "/008",
    })
    local _, errors = parser.parse(bufnr)
    assert.are_same({
      {
        message = "Malformed ID at start of line",
        lnum = 0,
        col = 0,
      },
    }, errors)
  end)

  it("errors on empty dirname", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "/008 /",
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = "No filename found",
        lnum = 0,
        col = 0,
      },
    }, errors)
  end)

  it("errors on duplicate names", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "foo",
      "foo/",
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = "Duplicate filename",
        lnum = 1,
        col = 0,
      },
    }, errors)
  end)

  it("errors on duplicate names for existing files", function()
    local file = test_adapter.test_set("/foo/a.txt", "file")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "a.txt",
      string.format("/%d a.txt", file[FIELD_ID]),
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = "Duplicate filename",
        lnum = 1,
        col = 0,
      },
    }, errors)
  end)

  it("ignores new dirs with empty name", function()
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      "/",
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)

  it("parses a rename as a delete + new", function()
    local file = test_adapter.test_set("/foo/a.txt", "file")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format("/%d b.txt", file[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { type = "new", id = file[FIELD_ID], name = "b.txt", entry_type = "file" },
      { type = "delete", id = file[FIELD_ID], name = "a.txt" },
    }, diffs)
  end)

  it("detects renamed files that conflict", function()
    local afile = test_adapter.test_set("/foo/a.txt", "file")
    local bfile = test_adapter.test_set("/foo/b.txt", "file")
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format("/%d a.txt", bfile[FIELD_ID]),
      string.format("/%d b.txt", afile[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    local first_two = { diffs[1], diffs[2] }
    local last_two = { diffs[3], diffs[4] }
    table.sort(first_two, function(a, b)
      return a.id < b.id
    end)
    table.sort(last_two, function(a, b)
      return a.id < b.id
    end)
    assert.are.same({
      { name = "b.txt", type = "new", id = afile[FIELD_ID], entry_type = "file" },
      { name = "a.txt", type = "new", id = bfile[FIELD_ID], entry_type = "file" },
    }, first_two)
    assert.are.same({
      { name = "a.txt", type = "delete", id = afile[FIELD_ID] },
      { name = "b.txt", type = "delete", id = bfile[FIELD_ID] },
    }, last_two)
  end)

  it("views link targets with trailing slashes as the same", function()
    local file = test_adapter.test_set("/foo/mydir", "link")
    file[FIELD_META] = { link = "dir/" }
    vim.cmd.edit({ args = { "oil-test:///foo/" } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format("/%d mydir/ -> dir/", file[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)

  describe("disable_changes adapter", function()
    before_each(function()
      test_adapter.disable_changes = true
    end)

    after_each(function()
      test_adapter.disable_changes = nil
    end)

    it("ignores new files", function()
      vim.cmd.edit({ args = { "oil-test:///foo/" } })
      local bufnr = vim.api.nvim_get_current_buf()
      local lines = { "newentry" }
      set_lines(bufnr, lines)
      local diffs, errors = parser.parse(bufnr)
      assert.are.same({}, diffs)
      assert.are.same({}, errors)
    end)

    it("detects new entries", function()
      vim.cmd.edit({ args = { "oil-test:///foo/" } })
      local bufnr = vim.api.nvim_get_current_buf()
      local file = cache.create_and_store_entry("oil:///root/", "newentry", "file")
      local cols = view.format_entry_cols(file, {}, {}, test_adapter)
      local lines = util.render_table({ cols }, {})
      set_lines(bufnr, lines)
      local diffs, errors = parser.parse(bufnr)
      assert.are.same({
        {
          id = file[FIELD_ID],
          type = "new",
          name = "newentry",
          entry_type = "file",
        },
      }, diffs)
      assert.are.same({}, errors)
    end)

    it("ignores name changes", function()
      vim.cmd.edit({ args = { "oil-test:///dir/" } })
      local bufnr = vim.api.nvim_get_current_buf()
      local file = test_adapter.test_set("/dir/foo.txt", "file")
      local lines = {
        string.format("/%d newname", file[FIELD_ID]),
      }
      set_lines(bufnr, lines)
      local diffs, errors = parser.parse(bufnr)
      assert.are.same({}, diffs)
      assert.are.same({}, errors)
    end)

    it("tolerates files with the same name", function()
      vim.cmd.edit({ args = { "oil-test:///dir/" } })
      local bufnr = vim.api.nvim_get_current_buf()
      local file = test_adapter.test_set("/dir/foo.txt", "file")
      local file2 = test_adapter.test_set("/dir/bar.txt", "file")
      local lines = {
        string.format("/%d newname", file[FIELD_ID]),
        string.format("/%d newname", file2[FIELD_ID]),
      }
      set_lines(bufnr, lines)
      local diffs, errors = parser.parse(bufnr)
      assert.are.same({}, diffs)
      assert.are.same({}, errors)
    end)

    it("ignores duplicate entries", function()
      vim.cmd.edit({ args = { "oil-test:///dir/" } })
      local bufnr = vim.api.nvim_get_current_buf()
      local file = test_adapter.test_set("/dir/foo.txt", "file")
      local lines = {
        string.format("/%d newname", file[FIELD_ID]),
        string.format("/%d newname", file[FIELD_ID]),
        string.format("/%d newname", file[FIELD_ID]),
        string.format("/%d newname", file[FIELD_ID]),
      }
      set_lines(bufnr, lines)
      local diffs, errors = parser.parse(bufnr)
      assert.are.same({}, diffs)
      assert.are.same({}, errors)
    end)
  end)
end)
