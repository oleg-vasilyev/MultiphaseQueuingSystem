blueConsole = 'background:#33b5e5; color: white'
greenConsole = 'background:#00C851; color: white'
orangeConsole = 'background:#ffbb33; color: white'
redConsole = 'background:#ff4444; color: white'



class Task
	constructor: (@name) ->
		@startTimeOfHFP = null
		@finishTimeOfHFP = null
		@startTimeOfHSP = null
		@finishTimeOfHSP = null
	getName: -> @name
	setStartTimeOfHFP: -> @startTimeOfHFP = new Date()
	setFinishTimeOfHFP: -> @finishTimeOfHFP = new Date()
	getExpectationsTimeOfHFP: -> @finishTimeOfHFP - @startTimeOfHFP
	setStartTimeOfHSP: -> @startTimeOfHSP = new Date()
	setFinishTimeOfHSP: -> @finishTimeOfHSP = new Date()
	getExpectationsTimeOfHSP: -> @finishTimeOfHSP - @startTimeOfHSP


class Channel
	constructor: (@name, @channelDistributionFunction) ->
		@status = 0
		@onFinishedCalculateTask = new Rx.Subject()
		@currentTask = null
	getName: -> @name
	isBusy: -> @status is 2 and @currentTask isnt null
	isCanTakeTask: -> @status is 0 and @currentTask is null
	takeTask: (task) ->
		that = @
		@status = 1
		@currentTask = task
		setTimeout ->
			that.onFinishedCalculateTask.next
				task: task
				channel: that
			that.status = 0
			that.currentTask = null
		, that.channelDistributionFunction()
	returnCurrentTaskAndBecomeFree: ->
		@status = 0
		outputTask = @currentTask
		@currentTask = null
		return outputTask
	setTask: (task) ->
		@status = 2
		@currentTask = task

class Source
	constructor: (@tasksCount, @sourceDistributionFunction) ->
		@onCompletedWork = new Rx.Subject()
		@onCreatedNewTask = new Rx.Subject()
	activate: ->
		that = @
		count = @tasksCount
		startLoop = ->
			if count > 0 
				taskName = "task №#{tasksCount - count + 1}"
				that.onCreatedNewTask.next(new Task(taskName))
				setTimeout(startLoop, that.sourceDistributionFunction())
				count--
			else
				that.onCompletedWork.next()
		startLoop()

class Hoarder 
	constructor: (@name, @size, @taskTimeLimit) ->
		@taskStack = []
		@onTaskWasDied = new Rx.Subject()
	getName: -> @name
	hasEnoughSpaceForNewTask: -> @taskStack.length < @size
	isEmpty: -> @taskStack.length is 0
	accumulateTask: (task) ->
		that = @
		@taskStack.push(task)
		setTimeout ->
			dyingTask = task
			length = that.taskStack.length
			that.taskStack = (t for t in that.taskStack when t.getName() isnt dyingTask.getName())
			if that.taskStack.length isnt length
				that.onTaskWasDied.next(dyingTask)
		, that.taskTimeLimit
	extractTask: -> @taskStack.pop()
	getAccumulatedTasksCount: -> @taskStack.length

class QueuingSystem
	constructor: (@source, @hoarderFirstPhase, @hoarderSecondPhase, @firstPhaseChannels, @secondPhaseChannels, @isDebugMode) ->
		@lostTasks = []
		@outputTasks = []
		@totalNumbersTheTasksInQS = []
		@onFinished = new Rx.Subject()
	start: ->
		that = @

		update = ->
			for firstPhaseChannel in that.firstPhaseChannels

				if firstPhaseChannel.isBusy() and that.hoarderSecondPhase.hasEnoughSpaceForNewTask()
						t = firstPhaseChannel.returnCurrentTaskAndBecomeFree()
						t.setStartTimeOfHSP()
						that.hoarderSecondPhase.accumulateTask(t)
						if that.isDebugMode then console.log "%c #{that.hoarderSecondPhase.getName()} accumulated #{t.getName()} ", greenConsole

				if firstPhaseChannel.isCanTakeTask() and not that.hoarderFirstPhase.isEmpty()
					t = that.hoarderFirstPhase.extractTask()
					t.setFinishTimeOfHFP()
					if that.isDebugMode then console.log "%c #{that.hoarderFirstPhase.getName()} extract #{t.getName()} ", greenConsole
					firstPhaseChannel.takeTask(t)
					if that.isDebugMode then console.log "%c #{firstPhaseChannel.getName()} take #{t.getName()} ", greenConsole
					break
						
			for secondPhaseChannel in that.secondPhaseChannels
				if secondPhaseChannel.isCanTakeTask() and not that.hoarderSecondPhase.isEmpty()
					t = that.hoarderSecondPhase.extractTask()
					t.setFinishTimeOfHSP()
					if that.isDebugMode then console.log "%c #{that.hoarderSecondPhase.getName()} extract #{t.getName()} ", greenConsole
					secondPhaseChannel.takeTask(t)
					if that.isDebugMode then console.log "%c #{secondPhaseChannel.getName()} take #{t.getName()} ", greenConsole
					break

		for firstPhaseChannel in that.firstPhaseChannels
			firstPhaseChannel.onFinishedCalculateTask.subscribe (data) ->
				ch = data.channel
				t = data.task
				if that.isDebugMode then console.log "%c #{ch.getName()} calculated #{t.getName()} ", orangeConsole
				
				if that.hoarderSecondPhase.hasEnoughSpaceForNewTask()
					t.setStartTimeOfHSP()
					that.hoarderSecondPhase.accumulateTask(t)
					if that.isDebugMode then console.log "%c #{that.hoarderSecondPhase.getName()} accumulated #{t.getName()} ", greenConsole
				else 
					firstPhaseChannel.setTask(t)
					if that.isDebugMode then console.log "%c #{t.getName()} blocked #{firstPhaseChannel.getName()} ", orangeConsole

		for secondPhaseChannel in that.secondPhaseChannels
			secondPhaseChannel.onFinishedCalculateTask.subscribe (data) ->
				ch = data.channel
				t = data.task
				if that.isDebugMode then console.log "%c #{ch.getName()} calculated #{t.getName()} ", orangeConsole
				that.outputTasks.push(t)
				if that.isDebugMode then console.log "%c #{t.getName()} is left ", redConsole

		hoarderFirstPhase.onTaskWasDied.subscribe (t) ->
			if that.isDebugMode then console.log "%c #{t.getName()} was died in #{hoarderFirstPhase.getName()} ", redConsole

		hoarderSecondPhase.onTaskWasDied.subscribe (t) ->
			if that.isDebugMode then console.log "%c #{t.getName()} was died in #{hoarderFirstPhase.getName()} ", redConsole

		@source.onCompletedWork.subscribe ->
			if that.isDebugMode then console.log "[Cleaning initialized]"
				
			updateLoop = ->
				isNoFirstPhaseCalcChannels = (firstPhaseChannel for firstPhaseChannel in that.firstPhaseChannels when not firstPhaseChannel.isCanTakeTask())?.length is 0
				isNoSecondPhaseCalcChannels = (secondPhaseChannel for secondPhaseChannel in that.secondPhaseChannels when not secondPhaseChannel.isCanTakeTask())?.length is 0
				isNeedsToBeCleaned = not (
					isNoFirstPhaseCalcChannels and 
					isNoSecondPhaseCalcChannels and 
					that.hoarderFirstPhase.isEmpty() and 
					that.hoarderSecondPhase.isEmpty())
				if isNeedsToBeCleaned
					update()
					setTimeout(updateLoop, 100)
				else
					if that.isDebugMode then console.log "[Cleaning done]"
					that.onFinished.next(that.outputTasks)
			updateLoop()
			
		@source.activate()

		@source.onCreatedNewTask.subscribe (task) ->
			if that.isDebugMode then console.log "%c #{task.getName()} is came ", blueConsole
			if that.hoarderFirstPhase.hasEnoughSpaceForNewTask()
				task.setStartTimeOfHFP()
				that.hoarderFirstPhase.accumulateTask(task)
				if that.isDebugMode then console.log "%c #{that.hoarderFirstPhase.getName()} accumulated #{task.getName()} ", greenConsole
			else 
				that.lostTasks.push(task)
				if that.isDebugMode then console.log "%c #{that.hoarderFirstPhase.getName()} was lost #{task.getName()} ", redConsole

			totalNumberTheTasksInQS = 0;
			for firstPhaseChannel in that.firstPhaseChannels
				if not firstPhaseChannel.isCanTakeTask() then totalNumberTheTasksInQS++

			for secondPhaseChannel in that.secondPhaseChannels
				if not secondPhaseChannel.isCanTakeTask() then totalNumberTheTasksInQS++
			
			totalNumberTheTasksInQS += that.hoarderFirstPhase.getAccumulatedTasksCount()

			totalNumberTheTasksInQS += that.hoarderSecondPhase.getAccumulatedTasksCount()

			that.totalNumbersTheTasksInQS.push(totalNumberTheTasksInQS)
			
			update()



class ChannelDistributionFunctionFactory
	getFunction: (channelIntensity) ->
		(_channelIntensity = channelIntensity) -> 
			(-1 / _channelIntensity) * Math.log(Math.random(), Math.E) * 1

class SourceDistributionFunctionFactory
	getFunction: (sourceIntensity) ->
		(_sourceIntensity = sourceIntensity) -> 
			(-1 / _sourceIntensity) * Math.log(Math.random(), Math.E) * 1



sourceDistributionFunctionFactory = new SourceDistributionFunctionFactory()
channelDistributionFunctionFactory = new ChannelDistributionFunctionFactory()

isDebugMode = false
sourceIntensity = 0.05 #0.05 -- 0.5
firstPhaseChannelIntensity = 0.01
secondPhaseChannelIntensity = 0.02
tasksCount = 100

source = new Source(tasksCount + 1, sourceDistributionFunctionFactory.getFunction(sourceIntensity))

hoarderFirstPhase = new Hoarder("Hoarder 1st phase", 6, 100)

hoarderSecondPhase = new Hoarder("Hoarder 2nd phase", 2, 200)

firstPhaseChannels = []
for id in [0..7]
	firstPhaseChannels.push(new Channel("Channel 1st phase | №" + id, channelDistributionFunctionFactory.getFunction(firstPhaseChannelIntensity)))

secondPhaseChannels = []
for id in [0..7]
	secondPhaseChannels.push(new Channel("Channel 2nd phase | №" + id, channelDistributionFunctionFactory.getFunction(secondPhaseChannelIntensity)))

queuingSystem = new QueuingSystem(source, hoarderFirstPhase, hoarderSecondPhase, firstPhaseChannels, secondPhaseChannels, isDebugMode)

queuingSystem.onFinished.subscribe (outputTasks) ->
	averageTimeExpectationsInHFP = 0
	maxTimeExpectationsInHFP = 0
	averageTimeExpectationsInHSP = 0
	maxTimeExpectationsInHSP = 0
	for outputTask in outputTasks
		currentExpectationsTimeOfHFP = outputTask.getExpectationsTimeOfHFP()
		currentExpectationsTimeOfHSP = outputTask.getExpectationsTimeOfHSP()

		if currentExpectationsTimeOfHFP > maxTimeExpectationsInHFP then maxTimeExpectationsInHFP = currentExpectationsTimeOfHFP
		if currentExpectationsTimeOfHSP > maxTimeExpectationsInHSP then maxTimeExpectationsInHSP = currentExpectationsTimeOfHSP 

		averageTimeExpectationsInHFP += currentExpectationsTimeOfHFP
		averageTimeExpectationsInHSP += currentExpectationsTimeOfHSP

	averageTimeExpectationsInHFP /= outputTasks.length
	averageTimeExpectationsInHSP /= outputTasks.length

	probability = (tasksCount - outputTasks.length) / tasksCount

	averageNumberOfTasksInQS = queuingSystem.totalNumbersTheTasksInQS.reduce (c, s) -> c + s
	averageNumberOfTasksInQS /= queuingSystem.totalNumbersTheTasksInQS.length

	console.log "%c Chance of losing task is #{probability.toFixed(3)} ", blueConsole
	console.log "%c Average expectations time in Hoarder 1st phase is #{averageTimeExpectationsInHFP.toFixed(3)}ms ", blueConsole
	console.log "%c Max expectations time in Hoarder 1st phase is #{maxTimeExpectationsInHFP.toFixed(3)}ms ", blueConsole
	console.log "%c Average expectations time in Hoarder 2st phase is #{averageTimeExpectationsInHSP.toFixed(3)}ms ", blueConsole
	console.log "%c Max expectations time in Hoarder 2st phase is #{maxTimeExpectationsInHSP.toFixed(3)}ms ", blueConsole
	console.log "%c Average number of tasks in system is #{averageNumberOfTasksInQS.toFixed(3)} ", blueConsole

queuingSystem.start()



