import gfapy

class RedundantLinearPaths:

  def __junction_junction_paths(self, sn, exclude):
    retval = []
    exclude.append(sn)
    s = self.segment(sn)
    for dL in s.dovetails("L"):
      eL = dL.other_end(gfapy.SegmentEnd(s, "L"))
      if (eL.name in exclude) or (len(eL.segment.dovetails(eL.end_type)) == 1):
        retval.append([True, eL, gfapy.SegmentEnd(s, "R"), True])
    for dR in s.dovetails("R"):
      eR = dR.other_end(gfapy.SegmentEnd(s, "R"))
      if (eR.name in exclude) or (len(eR.segment.dovetails(eR.end_type)) == 1):
        retval.append([True, gfapy.SegmentEnd(s, "R"), eR.invert(), True])
    return retval

  def __extend_linear_path_to_junctions(self, segpath):
    segfirst = self.segment(segpath[0].segment)
    segfirst_d = segfirst.dovetails(segpath[0].end_type.invert())
    redundant_first = (len(segfirst_d) > 0)
    if len(segfirst_d) == 1:
      segpath.insert(0, segfirst_d[0].other_end(segpath[0].invert()))
    segpath.insert(0, redundant_first)
    seglast = segment(segpath[-1].segment)
    seglast_d = seglast.dovetails(segpath[-1].end_type)
    redundant_last = (len(seglast_d) > 0)
    if len(seglast_d) == 1:
      segpath.append(seglast_d[0].other_end(segpath[-1].invert()))
    segpath.append(redundant_last)

  def __link_duplicated_first(self, merged, first, is_reversed, jntag):
    # annotate junction
    if jntag is None:
      jntag = "jn"
    if not first.get(jntag):
      first.set(jntag, {"L":[],"R":[]})
    if is_reversed:
      first.get(jntag)["L"].append([merged.name, "-"])
    else:
      first.get(jntag)["R"].append([merged.name, "+"])
    # create temporary link
    ln = len(first.sequence)
    if self._version == "gfa1":
      tmp_link = gfapy.Line.Edge.Link([first.name, \
        "-" if is_reversed else "+", merged.name, "+", \
        "{}M".format(ln), "co:Z:temporary"])
      self.add_line(tmp_link)
    elif self._version == "gfa2":
      tmp_link = gfapy.Line.Edge.GFA2(["*",first.name + \
        ("-" if is_reversed else "+"), merged.name+"+",
        "0" if is_reversed else str(ln-1), # on purpose fake
        "1" if is_reversed else "{}$".format(ln), # on purpose fake
        0, str(ln), "{}M".format(ln), "co:Z:temporary"])
      self.add_line(tmp_link)
    else:
      raise gfapy.AssertionError()

  def __link_duplicated_last(self, merged, last, is_reversed, jntag):
    # annotate junction
    if jntag is None:
      jntag = "jn"
    if not last.get(jntag):
      last.set(jntag, {"L":[],"R":[]})
    if is_reversed:
      last.get(jntag)["R"].append([merged.name, "-"])
    else:
      last.get(jntag)["L"].append([merged.name, "+"])
    # create temporary link
    ln = len(last.sequence)
    if self._version == "gfa1":
      tmp_link = gfapy.Line.Edge.Link([merged.name, "+",
          last.name, "-" if is_reversed else "+",
          "{}M".format(ln), "co:Z:temporary"])
      self.add_line(tmp_link)
    elif self._version == "gfa2":
      mln = len(merged.sequence)
      tmp_link = gfapy.Line.Edge.GFA2(["*",merged.name+"+", \
        last_name+("-" if is_reversed else "+"),
        str(mln - ln), "{}$".format(mln),
        str(ln-1) if is_reversed else "0", # on purpose fake
        "{}$".format(ln) if is_reversed else "1", # on purpose fake
        "{}M".format(ln), "co:Z:temporary"])
      self.add_line(tmp_link)
    else:
      raise gfapy.AssertionError()

  def __remove_junctions(self, jntag):
    if jntag is None:
      jntag = "jn"
    for s in self.segments:
      jndata = s.get(jntag)
      if jndata:
        ln = len(s.sequence)
        for m1, dir1 in jndata["L"].items():
          for m2, dir2 in jndata["R"].items():
            if self._version == "gfa1":
              l = gfapy.Line.Edge.Link([m1,dir1,m2,dir2,"{}M".format(ln)])
              self.add_line(l)
            elif self._version == "gfa2":
              m1ln = len(self.segment(m1).sequence)
              m2ln = len(self.segment(m2).sequence)
              r1 = (dir1 == "-")
              r2 = (dir2 == "-")
              l = gfapy.Line.Edge.GFA2(["*", m1+dir1, m2+dir2,
                 "0" if r1 else str(m1ln-ln),
                 str(ln) if r1 else str(m1ln)+"$",
                 "0" if r2 else str(m2ln-ln),
                 str(ln) if r1 else str(m2ln)+"$",
                 str(ln)+"M"])
              self.add_line(l)
            else:
              raise gfapy.AssertionError()
        s.disconnect()

