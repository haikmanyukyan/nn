local LookupTable, parent = torch.class('nn.LookupTable', 'nn.Module')

LookupTable.__version = 3

function LookupTable:__init(nIndex, ...)
   parent.__init(self)
   local arg = {...}

   if select('#', ...) == 1 and type(arg[1]) ~= "number" then
      local size = arg[1]
      self.size = torch.LongStorage(#size + 1)
      for i=1,#size do
         self.size[i+1] = size[i]
      end
   else
      self.size = torch.LongStorage(select('#', ...)+1)
      for i=1,select('#',...) do
         self.size[i+1] = arg[i]
      end
   end

   self.size[1] = nIndex
   
   batchSize = torch.LongTensor(#self.size + 1)
   batchSize:narrow(1, 2,#self.size):copy(self.size)
   batchSize[1] = 1
   self.batchSize = batchSize:storage()
   
   self.weight = torch.Tensor(self.size)
   self.gradWeight = torch.Tensor(self.size):zero()
   self.inputs = {}

   self:reset()
end

function LookupTable:reset(stdv)
   stdv = stdv or 1
   if nn.oldSeed then
      self.weight:apply(function()
         return torch.normal(0, stdv)
      end)
   else
      self.weight:normal(0, stdv)
   end
end

function LookupTable:updateOutput(input)
   if input:dim() == 1 then
      local nIndex = input:size(1)
      self.size[1] = nIndex
      self.output:resize(self.size)

      for i=1,nIndex do
         self.output:select(1, i):copy(self.weight:select(1, input[i]))
      end
   elseif input:dim() == 2 then
      local nExample = input:size(1)
      local nIndex = input:size(2)
      self.batchSize[1] = nExample
      self.batchSize[2] = nIndex
      self.output:resize(self.batchSize)
      
      for i=1,nExample do
         local output = self.output:select(1, i)
         for j=1,nIndex do
            output:select(1, j):copy(self.weight:select(1, input[j]))
         end
      end
   end

   return self.output
end

function LookupTable:zeroGradParameters()
   for k,_ in pairs(self.inputs) do
      self.gradWeight:select(1, k):zero()
   end
   self.inputs = {}
end

function LookupTable:accGradParameters(input, gradOutput, scale)
   for i=1,input:size(1) do
      local k = input[i]
      self.inputs[k] = true
      self.gradWeight:select(1, k):add(scale, gradOutput:select(1, i))
   end
end

function LookupTable:accUpdateGradParameters(input, gradOutput, lr)
   for i=1,input:size(1) do
      self.weight:select(1, input[i]):add(-lr, gradOutput:select(1, i))
   end
end

function LookupTable:updateParameters(learningRate)
   for k,_ in pairs(self.inputs) do
      self.weight:select(1, k):add(-learningRate, self.gradWeight:select(1, k))
   end
end

-- we do not need to accumulate parameters when sharing
LookupTable.sharedAccUpdateGradParameters = LookupTable.accUpdateGradParameters
