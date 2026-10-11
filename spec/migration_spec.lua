local migration = require('canola.migration')

local github = 'https://github.com/barrettruth/canola.nvim.git'
local message = table.concat({
  '[canola.nvim] This repository will be removed from GitHub on October 31, 2026.',
  'Install from Forgejo: https://forge.barrettruth.com/barrettruth/canola.nvim with branch = "canola".',
  'See :help canola-github-removal.',
}, ' ')

local function drain()
  local done = false
  vim.schedule(function()
    done = true
  end)
  assert.is_true(vim.wait(1000, function()
    return done
  end))
end

describe('GitHub migration', function()
  local notify
  local system
  local executable

  before_each(function()
    drain()
    notify = stub(vim, 'notify_once')
    executable = stub(vim.fn, 'executable', function()
      return 1
    end)
    system = stub(vim, 'system')
  end)

  after_each(function()
    drain()
    notify:revert()
    executable:revert()
    system:revert()
  end)

  it('preserves origin matching', function()
    for _, origin in ipairs({
      'https://github.com/barrettruth/canola.nvim',
      'http://github.com/barrettruth/canola.nvim',
      'git://github.com/barrettruth/canola.nvim',
      'ssh://git@github.com/barrettruth/canola.nvim',
      'git@github.com:barrettruth/canola.nvim',
    }) do
      assert.is_true(migration.is_github_origin(origin))
      assert.is_true(migration.is_github_origin(origin .. '.git/'))
    end
    for _, origin in ipairs({
      false,
      {},
      'https://forge.barrettruth.com/barrettruth/canola.nvim',
      'https://github.com/stevearc/oil.nvim',
      'https://github.com/barrettruth/canola.nvim-other',
    }) do
      assert.is_false(migration.is_github_origin(origin))
    end
    assert.is_false(migration.is_github_origin(nil))
  end)

  it('starts Git before returning and schedules the notification', function()
    local complete
    system:revert()
    system = stub(vim, 'system', function(command, opts, callback)
      assert.same({ 'git', '-C', '/plugin path', 'config', '--get', 'remote.origin.url' }, command)
      assert.same({ text = true }, opts)
      complete = callback
      return {
        wait = function()
          error('The startup check must not wait')
        end,
      }
    end)
    migration.warn_if_github_source_async('/plugin path')
    assert.stub(system).was_called(1)
    assert.stub(notify).was_not_called()
    complete({ code = 0, stdout = github .. '\n' })
    assert.stub(notify).was_not_called()
    drain()
    assert.stub(notify).was_called_with(message, vim.log.levels.WARN)
  end)

  it('ignores unsuccessful Git commands and other origins', function()
    system:revert()
    for _, result in ipairs({
      { code = 1, stdout = github },
      { code = 128, stdout = '' },
      { code = 0 },
      { code = 0, stdout = 'https://forge.barrettruth.com/barrettruth/canola.nvim' },
    }) do
      system = stub(vim, 'system', function(_, _, callback)
        callback(result)
      end)
      migration.warn_if_github_source_async('/plugin')
      drain()
      assert.stub(notify).was_not_called()
      system:revert()
    end
  end)

  it('does not start Git when Git is absent', function()
    executable:revert()
    executable = stub(vim.fn, 'executable', function()
      return 0
    end)
    migration.warn_if_github_source_async()
    assert.stub(system).was_not_called()
    assert.stub(notify).was_not_called()
    assert.is_nil(migration.origin('/plugin'))
    assert.is_false(migration.warn_if_github_source('/plugin'))
  end)

  it('ignores process creation errors', function()
    system:revert()
    system = stub(vim, 'system', function()
      error('Cannot start Git')
    end)
    migration.warn_if_github_source_async('/plugin')
    assert.stub(system).was_called(1)
    assert.stub(notify).was_not_called()
  end)

  it('reads an actual Git origin without a fast-event notification', function()
    system:revert()
    executable:revert()
    local root = vim.fn.tempname() .. ' plugin'
    vim.fn.mkdir(root, 'p')
    local function git(...)
      local command = { 'git', '-C', root }
      vim.list_extend(command, { ... })
      assert.equal(0, vim.system(command):wait().code)
    end
    git('init', '--quiet')
    git('remote', 'add', 'origin', github)
    local received = false
    notify:revert()
    notify = stub(vim, 'notify_once', function(text, level)
      assert.is_false(vim.in_fast_event())
      assert.equal(message, text)
      assert.equal(vim.log.levels.WARN, level)
      received = true
    end)
    migration.warn_if_github_source_async(root)
    assert.is_false(received)
    assert.is_true(vim.wait(3000, function()
      return received
    end))
    assert.equal(github, migration.origin(root))
    assert.is_true(migration.warn_if_github_source(root))
    vim.fn.delete(root, 'rf')
  end)
end)
