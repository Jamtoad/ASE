--------------------------------------------------------------------------------
--- ASE (All Seeing Eye)
--[[
  Goals
    * Dependency free!
    * Flatten the learning curve of Reactive Programming!
    * Provide all the Observers you need!
    
  Implementations
    * concat
    * startWith
    * withLatestFrom
    * iif
    * catch
    * debounceTime
    * distinctUntilChanged
    * take
    * takeUntil
    * share
    * shareReplay
    * bufferTime
    * concatMap
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
--[[
  Function : New
  Purpose : Creates a new observable (This is the backbone of everything)
  Parameters :
    * OnSubscribe (Function) : The callback function to run upon subscription.
  Returns :
    * Observable : An Observable that can either be subscribed to or piped.
  Example :
    local function ObserveHumanoidDied(Humanoid)
      return ASE.New(function(Fire)
        local HumanoidDiedConnection = Humanoid.Died:Connect(Fire)
        
        return function()
          HumanoidDiedConnection:Disconnect()
        end
      end)
    end
]]
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

function ASE.MergeMap(Callback, ResultSelector)
  return function(Source)
    return ASE.New(function(Fire, Fail, Complete)
      local Pending = 0
      local TopComplete = false
      local OuterCleanupCallback
      
      OuterCleanupCallback = Source.Subscribe(
        function(...)
          local OuterValue = ...
          local Observable = Callback(...)
          local InnerCleanupCallback
          
          Pending += 1

          InnerCleanupCallback = Observable.Subscribe(
            function(...)
              return if ResultSelector
                then Fire(ResultSelector(OuterValue, ...))
                else Fire(...)
            end,
            function(...)
              Fail(...)
            end,
            function()
              InnerCleanupCallback()
              
              Pending -= 1
              
              if Pending == 0 and TopComplete then
                Complete()
                OuterCleanupCallback()
              end
            end
          )
        end,
        function(...)
          Fail(...)
          OuterCleanupCallback()
        end,
        function()
          TopComplete = true
          
          if Pending == 0 then
            Complete()
            OuterCleanupCallback()
          end
        end
      )
    end)
  end
end

function ASE.ObserveTimer(InitialDelay, Seconds)
  return ASE.New(function(Fire)
    local Thread = task.spawn(function()
      if InitialDelay and InitialDelay > 0 then
        task.wait(InitialDelay)
      end

      while true do
        Fire()
        
        task.wait(Seconds)
      end
    end)

    return function()
      task.cancel(Thread)
    end
  end)
end

function ASE.ObserveInterval(Seconds)
  return ASE.ObserveTimer(0, Seconds)
end

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
  return ASE.New(function(Fire, Fail, Complete)
    local Pending = 0
    local Latest = {}
    local CleanupCallbacks = {}

    for Key, Observable in Observables do
      Pending += 1
      Latest[Key] = ""
      
      table.insert(CleanupCallbacks, Observable.Subscribe(
        function(Value)
          Latest[Key] = Value
          
          for _, Value in Latest do
            if Value == "" then
              return
            end
          end

          Fire(table.clone(Latest))
        end,
        function(...)
          Pending -= 1
          
          Fail(...)
        end,
        function()
          Pending -= 1
          
          if Pending == 0 then
            Complete()
          end
        end)
      )
    end

    return function()
      for _, CleanupCallback in CleanupCallbacks do
        CleanupCallback()
      end
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
      
      RenderSteppedConnection = RunService.RenderStepped:Connect(Fire)
      
      return function()
        RenderSteppedConnection:Disconnect()
      end
    end)
  end
  else nil

function ASE.ObserveHeartbeat()
  return ASE.New(function(Fire)
    local HearbeatConnection
    
    HearbeatConnection = RunService.Heartbeat:Connect(Fire)

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