--------------------------------------------------------------------------------
--- ASE (All Seeing Eye)
--[[
  Goals
    * Dependency free!
    * Flatten the learning curve of Reactive Programming!
    * Provide all the Observers you need!
    
  Implementations
    * combineLatest
    * concat
    * merge
    * startWith
    * withLatestFrom
    * iif
    * from
    * of
    * fromEvent
    * catch
    * debounceTime
    * distinctUntilChanged
    * filter
    * take
    * takeUntil
    * share
    * shareReplay
    * bufferTime
    * concatMap
    * map
    * mergeMap aka flatMap
    * scan
    * switchMap
    * tap
]]
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
--- Root
local ASE = {}
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
--- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
--- Exported Functions
function ASE.New(OnSubscribe)    
  local function Subscribe(FireCallback, FailCallback, CompleteCallback)
    local CleanupCallback

    CleanupCallback = OnSubscribe(
      FireCallback,
      function()
        if FailCallback then
          FailCallback()
        end
        
        if CleanupCallback then
          CleanupCallback()
        end
      end,
      function()
        if CompleteCallback then
          CompleteCallback()
        end

        if CleanupCallback then
          CleanupCallback()
        end
      end
    )

    return CleanupCallback
  end

  local function Pipe(Transformers)
    local Result = {
      ["Subscribe"] = Subscribe
    }

    for _, Transformer in Transformers do
      Result = Transformer(Result)
    end
    return Result
  end

  return {
    ["Subscribe"] = Subscribe,
    ["Pipe"] = Pipe 
  }
end

ASE.Empty = ASE.New(function(_, _, Complete)
  Complete()
end)

ASE.Never = ASE.New(function() end)

function ASE.Filter(Predicate)
  return function(Source)
    return ASE.New(function(Fire, Fail, Complete)
      return Source.Subscribe(function(...)
        if Predicate(...) then
          Fire(...)
        end
      end, Fail, Complete)
    end)
  end
end

function ASE.Map(Callback)
  return function(Source)
    return ASE.New(function(Fire, Fail, Complete)
      return Source.Subscribe(function(...)
        Fire(Callback(...))
      end, Fail, Complete)
    end)
  end
end

function ASE.Scan(Accumulator, Seed)
  return function(Source)
    return ASE.New(function(Fire, Fail, Complete)
      local Result = Seed

      return Source.Subscribe(function(...)
        Result = Accumulator(Result, ...)
        Fire(Result)
      end, Fail, Complete)
    end)
  end
end

--function ASE.MergeMap(Callback, ResultSelector)
--  return function(Source)
--    return ASE.New(function(Fire, Fail, Complete)
--      local pendingCount = 0
--      local topComplete = false

--      maid:GiveTask(source:Subscribe(
--        function(...)
--          local outerValue = ...

--          local observable = project(...)
--          assert(Observable.isObservable(observable), "Bad observable from project")

--          pendingCount = pendingCount + 1

--          local innerMaid = Maid.new()

--          local subscription = innerMaid:Add(observable:Subscribe(
--            function(...)
--              -- Merge each inner observable
--              if resultSelector then
--                sub:Fire(resultSelector(outerValue, ...))
--              else
--                sub:Fire(...)
--              end
--            end,
--            function(...)
--              sub:Fail(...)
--            end, -- Emit failure automatically
--            function()
--              innerMaid:DoCleaning()
--              pendingCount = pendingCount - 1
--              if pendingCount == 0 and topComplete then
--                sub:Complete()
--                maid:DoCleaning()
--              end
--            end))

--          if subscription:IsPending() then
--            local key = maid:GiveTask(innerMaid)

--            -- Cleanup
--            innerMaid:GiveTask(function()
--              maid[key] = nil
--            end)
--          else
--            subscription:Destroy()
--          end
--        end,
--        function(...)
--          sub:Fail(...) -- Also reflect failures up to the top!
--          maid:DoCleaning()
--        end,
--        function()
--          topComplete = true
--          if pendingCount == 0 then
--            sub:Complete()
--            maid:DoCleaning()
--          end
--        end))

--      return function()
--        --- Cleanup
--      end
--    end)
--  end
--end

function ASE.Observe(...)
  local Arguments = if type(...) ~= "table" then {...} else ...
  
  return ASE.New(function(Fire, _, Complete)
    for _, Argument in Arguments do
      Fire(Argument)
    end
    
    Complete()
  end)
end

function ASE.ObserveCombinedLatest(Observables)
  local initialPending = 0
  local defaultLatest = {}
  
  for key, value in pairs(Observables) do
    initialPending = initialPending + 1
    defaultLatest[key] = ""
  end

  return ASE.New(function(Fire, Fail, Complete)
    local pending = initialPending
    local latest = table.clone(defaultLatest)

    if pending == 0 then
      Fire(latest)
      Complete()
      return
    end

    local function fireIfAllSet()
      for _, value in pairs(latest) do
        if value == "" then
          return
        end
      end
      
      Fire(table.clone(latest))
    end

    for key, observer in pairs(Observables) do
      observer.Subscribe(
        function(value)
          latest[key] = value
          fireIfAllSet()
        end,
        function(...)
          pending = pending - 1
          Fail(...)
        end,
        function()
          pending = pending - 1
          if pending == 0 then
            Complete()
          end
        end
      )
    end

    return function()
      
    end
  end)
end

function ASE.ObserveMerged(Observables)
  return ASE.New(function(Fire, Fail, Complete)
    local CleanupCallbacks = {}

    for _, Observable in Observables do
      table.insert(CleanupCallbacks, Observable.Subscribe(Fire, Fail, Complete))
    end

    return function()
      for _, CleanupCallback in CleanupCallbacks do
        CleanupCallback()
      end
    end
  end)
end

function ASE.ObserveSignal(Signal)
  return ASE.New(function(Fire)
    local Connection = Signal:Connect(Fire)
    
    return function()
      Connection:Disconnect()
    end
  end)
end

function ASE.ObservePlayers(Predicate)
  return ASE.New(function(Fire)
    local PlayerAddedConnection
    
    local function HandlePlayer(...)
      return if not Predicate or Predicate(...)
        then Fire(...)
        else nil
    end
    
    PlayerAddedConnection = Players.PlayerAdded:Connect(HandlePlayer)

    for _, Player in Players:GetPlayers() do
      HandlePlayer(Player)
    end

    return function()
      PlayerAddedConnection:Disconnect()
    end
  end)
end

ASE.ObserveLocalPlayer = if RunService:IsClient()
  then function()
    return ASE.ObservePlayers(function(Player)
      return Player == Players.LocalPlayer
    end)
  end
  else nil

function ASE.ObserveCharacters(Predicate)
  return ASE.New(function(Fire)
    local PlayerAddedConnection, CharacterAddedConnection
    
    local function HandleCharacter(...)
      return if not Predicate or Predicate(...)
        then Fire(...)
        else nil
    end
    
    PlayerAddedConnection = ASE.ObservePlayers().Subscribe(function(Player)
      CharacterAddedConnection = Player.CharacterAdded:Connect(function(Character)
        HandleCharacter(Character, Player)
      end)
      
      if Player.Character then
        HandleCharacter(Player.Character, Player)
      end
    end)
    
    return function()
      PlayerAddedConnection()
      CharacterAddedConnection:Disconnect()
    end
  end)
end

ASE.ObserveLocalCharacter = if RunService:IsClient()
  then function()
    return ASE.ObserveCharacters(function(_, Player)
      return Player == Players.LocalPlayer
    end)
  end
  else nil

ASE.ObserveRenderStepped = if RunService:IsClient()
  then function()
    return ASE.New(function(Fire)
      local RenderSteppedConnection
      
      RenderSteppedConnection = RunService.RenderStepped:Connect(function(...)
        Fire(...)
      end)
      
      return function()
        RenderSteppedConnection:Disconnect()
      end
    end)
  end
  else nil

function ASE.ObserveHeartbeat()
  return ASE.New(function(Fire)
    local HearbeatConnection
    
    HearbeatConnection = RunService.Heartbeat:Connect(function(...)
      Fire(...)
    end)

    return function()
      HearbeatConnection:Disconnect()
    end
  end)
end

function ASE.ObserveTag(Tag)
  return ASE.New(function(Fire, _, Complete)
    local InstanceAddedConnection

    InstanceAddedConnection = CollectionService:GetInstanceAddedSignal(Tag):Connect(Fire)
    
    for _, Instance in CollectionService:GetTagged(Tag) do
      Fire(Instance)
    end

    return function()
      InstanceAddedConnection:Disconnect()
    end
  end)
end

function ASE.ObserveAttribute(Instance, Attribute)
  return ASE.New(function(Fire)
    local AttributeChangedConnection
    
    AttributeChangedConnection = Instance:GetAttributeChangedSignal(Attribute):Connect(Fire)
    
    Fire(Instance:GetAttribute(Attribute))
    
    return function()
      AttributeChangedConnection:Disconnect()
    end
  end)
end

function ASE.ObserveProperty(Instance, Property)
  return ASE.New(function(Fire)
    local PropertyChangedConnection

    PropertyChangedConnection = Instance:GetPropertyChangedSignal(Property):Connect(Fire)

    Fire(Instance[Property])

    return function()
      PropertyChangedConnection:Disconnect()
    end
  end)
end
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
--- Return
return ASE