local r,n=...n=n or{}n.MSUF_CastbarRegistry=n.MSUF_CastbarRegistry or{}local n=n.MSUF_CastbarRegistry
n.bars=n.bars or{}function n:Register(r,t,a,e)if not r then return end n.bars[r]={unit=t,frame=a,styleGetter=e,}end function n:Unregister(r)if not r then return end n.bars[r]=nil
end function n:Get(r)if not r then return nil end return n.bars[r]end function n:Iterate()return pairs(n.bars)end