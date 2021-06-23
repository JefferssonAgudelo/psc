
import adios2
import os
import numpy as np

_ad = adios2.ADIOS()

class file:
    def __init__(self, path, what, time):
        self._io = _ad.DeclareIO('io')
        self._engine = self._io.Open(os.path.join(path, f'{what}.{time:09d}.bp'), adios2.Mode.Read)
        
    def read(self, varname, sel_start, sel_count):
        var = self._io.InquireVariable(varname)
        var.SetSelection((sel_start[::-1], sel_count[::-1]))
        arr = np.empty(sel_count, dtype='f', order='F')
        self._engine.Get(var, arr, adios2.Mode.Sync)
        return arr[:,:,:,0]

