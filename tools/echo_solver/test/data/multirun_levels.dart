// Random levels (grid, runLimit) whose unpruned optimum uses 2 or 3 runs,
// found offline with a seeded generator (seed 2026, 4-6 x 3-4, 1-3 plates
// with 1-2 doors each, walls 25%, runLimit 2-3). The comment on each line is
// the unpruned best score and the number of runs it used.
const multiRunLevels = <(List<String>, int)>[
  (['bS#..c', 'a.#...', '.C..BC', 'BA..E.'], 3), // best 11, 3 runs
  (['#A#A.', 'E#aS.', '..BBb'], 3), // best 8, 2 runs
  (['#..S#', 'EA..b', 'B#.a.'], 3), // best 6, 2 runs
  (['Sa.b', '..BA', 'cCCE'], 3), // best 6, 2 runs
  (['.B.#.', '.#..a', 'E.A.b', '#..BS'], 2), // best 7, 2 runs
  (['BcAE', 'b.AB', 'C.aS'], 2), // best 5, 2 runs
  (['EC..', '#.#b', 'a..c', 'SA.B'], 2), // best 10, 2 runs
  (['..aBC#', '.Sb.AE', '#CcAB.'], 3), // best 6, 2 runs
  (['..aS', 'bA#B', '..BE'], 2), // best 10, 2 runs
  (['.EA##.', '...B..', '####.#', '.bA.Sa'], 2), // best 11, 2 runs
  (['...Cb', '.EBAS', '.ac.B'], 3), // best 7, 2 runs
  (['EB...', 'B.ab.', '#.#S.', '##.AA'], 2), // best 6, 2 runs
  (['C#AC', '.#bS', 'aB..', '#EAc'], 2), // best 5, 2 runs
  (['..CSb', 'BA.a.', '#.#..', 'c.EAC'], 2), // best 5, 2 runs
  (['c.a..#', 'CBSbCE', 'B..A#.'], 2), // best 8, 2 runs
  (['#CEBa', 'b.CA.', 'c.S.A', '....B'], 3), // best 6, 2 runs
  (['.C.CcA', 'b.A.B.', '#E.BSa'], 2), // best 10, 2 runs
  (['.#Ba.', 'S.c#E', '#CbAC'], 3), // best 10, 2 runs
  (['..a#', '#...', '.#.S', 'EA..'], 3), // best 8, 2 runs
  (['E###S#', '.##...', 'A...a#', '.#..#.'], 2), // best 10, 2 runs
  (['..BBEC', '....Ac', 'a...b#', '...#S#'], 2), // best 6, 2 runs
  (['...BE', 'A..A.', 'SabCB', '.c..#'], 2), // best 7, 2 runs
  (['B.#E.', '.S#.C', 'ab.A.', 'cC..B'], 3), // best 7, 2 runs
  (['..Bb##', '#A...a', 'c##.#B', 'S..C.E'], 2), // best 6, 2 runs
  (['#..#..', '..AS.a', 'E.A.##'], 2), // best 7, 2 runs
  (['C..A', '.b#.', 'SaBE', 'BACc'], 3), // best 6, 2 runs
  (['.a..BE', '.#.b.#', '...S#.', '..A.#.'], 2), // best 5, 2 runs
  (['AaBE', 'S#.B', '.b.#'], 2), // best 8, 2 runs
  (['.#.c', '##CE', 'aBA.', 'SbCB'], 3), // best 6, 2 runs
  (['b.a...', '.....#', 'S..B..', '.#.AE.'], 3), // best 7, 2 runs
  (['E.A.S.', '.#A.a.', '......', '#.#...'], 2), // best 5, 2 runs
  (['.aSb', '##..', '#.A.', 'EB.B'], 3), // best 7, 3 runs
  (['CA.#.', 'E.#B.', '#BcSb', 'a#..#'], 3), // best 5, 2 runs
  (['##E..', '..##B', '#Sab.', '#..#A'], 2), // best 9, 2 runs
  (['#CS.', 'Ba#c', 'EbA.'], 3), // best 8, 2 runs
  (['.#B.c', 'B##ba', 'CEASC'], 3), // best 6, 2 runs
  (['.ba.B#', '##.#c.', 'EC.#..', 'CA.S.#'], 2), // best 8, 2 runs
  (['.AE.', 'SCcA', 'aCb.', '#..B'], 2), // best 4, 2 runs
  (['EBC.', '#.b.', 'ABSc', 'a..C'], 3), // best 5, 2 runs
  (['caBE', '.CSA', 'C.bA'], 2), // best 4, 2 runs
  (['SCbA', 'a#AC', 'cBBE'], 3), // best 10, 3 runs
  (['A.ScB', '#CBa#', '#..#.', '.b..E'], 2), // best 8, 2 runs
  (['#Sa#', '#.B.', 'EAA.', 'b...'], 3), // best 4, 2 runs
  (['a...', 'S.AE', '..##'], 3), // best 4, 2 runs
  (['B..B.', 'C.b.a', 'S#EC.', '.cA..'], 2), // best 8, 2 runs
  (['B..S.', 'c..#b', 'aA#EC', '#C.A#'], 2), // best 10, 2 runs
  (['C..cB', '.b#..', 'B.aAA', '.S.#E'], 3), // best 7, 2 runs
  (['.E..#S', '.##A.a', '...#..'], 3), // best 7, 2 runs
  (['acb.', 'S...', '.ACA', 'BE#B'], 3), // best 4, 2 runs
  (['##B..', 'a.S..', '.Ab..', '#E#B#'], 2), // best 6, 2 runs
  (['#.#EA', 'B.#a.', 'Sb.B.'], 3), // best 6, 2 runs
  (['A#a#E', 'b###.', 'SB...'], 3), // best 8, 2 runs
  (['CB..', 'cbAa', 'SCEB'], 2), // best 4, 2 runs
  (['#AE#A', '#.##.', 'S....', '..a#.'], 3), // best 8, 2 runs
  (['.EA.', '##..', '.##a', 'S...'], 2), // best 12, 2 runs
  (['a.A.S#', 'E..B..', '#B..#b'], 2), // best 10, 2 runs
  (['S...A.', 'a#.#.#', '.#.#E.'], 3), // best 7, 2 runs
  (['B.B..', '..A..', 'A#.#b', 'Sa#.E'], 2), // best 10, 2 runs
  (['bCaS', 'B.CA', '#E#c'], 3), // best 9, 2 runs
  (['.#A.b', '....B', '.a.A.', 'SB#.E'], 2), // best 8, 2 runs
  (['ACE.', 'ASB.', 'b..c', 'a#BC'], 3), // best 6, 2 runs
  (['.BS.C', '.ca.#', '.A.AE', '...b#'], 3), // best 5, 2 runs
  (['.bA#.E', '..CBc.', '..SBAa'], 2), // best 11, 2 runs
  (['.bAB#.', 'aS.#CE', '.#..Ac', '..C.#.'], 3), // best 7, 2 runs
  (['.A##b.', '..#.Sa', 'EB..#.', 'B#....'], 2), // best 6, 2 runs
  (['EA...', '#.ASa', '..#..'], 2), // best 5, 2 runs
  (['S#AB#', '..A.E', 'ba.B.'], 2), // best 9, 2 runs
  (['#a#...', 'E##.S#', '.C..cA', '..B.b.'], 3), // best 7, 2 runs
  (['#.aA.', 'C.#EA', '.B.B#', '.bcS.'], 2), // best 6, 2 runs
  (['#.#S', 'AE#.', 'aB.b', '.#.B'], 2), // best 7, 2 runs
  (['SAb.', 'a#EB', '.#..'], 2), // best 5, 2 runs
  (['.#a.', 'A#..', 'EAS#'], 3), // best 6, 2 runs
  (['A.B...', 'E..#Sa', 'bCC.c.', '##...#'], 2), // best 7, 2 runs
  (['cEC.#', '.ASab', 'B#...'], 2), // best 4, 2 runs
  (['#aSA', '..AE', 'bB..', '....'], 3), // best 4, 2 runs
  (['...A.', '..#Aa', '..#..', 'E..#S'], 3), // best 12, 2 runs
  (['cb...', 'a.CCB', '#SAE#'], 2), // best 6, 2 runs
  (['..a.c', 'ASC#.', 'bAE#B'], 3), // best 6, 2 runs
  (['....#B', 'c..#..', '#.CabB', '.S#.EA'], 2), // best 10, 2 runs
  (['.CcA#E', 'S....B', 'a.b#..', '#...#.'], 2), // best 9, 2 runs
  (['B..#EC', '..#b#.', 'A..S.c', 'B.#a.#'], 3), // best 7, 2 runs
  (['...c.', 'a.b#.', 'S.BAE', '..AC.'], 3), // best 7, 2 runs
  (['.Cc#A', '.SAbE', 'a.#B.'], 3), // best 7, 2 runs
  (['aBCc', 'SAE.', 'ABCb'], 2), // best 4, 2 runs
  (['...S.a', '#A..BB', 'Eb#.A#'], 2), // best 7, 2 runs
  (['aCAC', 'BcSb', 'EB..'], 2), // best 4, 2 runs
  (['Ab#c', 'aCBE', '..SA'], 3), // best 8, 2 runs
  (['B#...', '##aE.', '..B.#', 'SbA..'], 3), // best 6, 2 runs
  (['..A...', '...Cb.', '.c#.aE', 'S..B.B'], 3), // best 10, 2 runs
  (['c..S.#', '.#a#C.', '..C.AB', 'b.B..E'], 2), // best 11, 2 runs
  (['E.AB', '##.a', 'b..S'], 2), // best 6, 2 runs
  (['b.BE', 'BSAc', 'aCCA'], 3), // best 6, 2 runs
  (['.BC.', '#AEb', 'a.BA', 'S#cC'], 3), // best 5, 2 runs
  (['Ccb...', 'C.#...', '.S..AB', '..a.#E'], 3), // best 10, 3 runs
  (['B..S', '#..b', 'E#.a', '.AB.'], 3), // best 10, 3 runs
  (['A..c', 'bBBS', 'EACa'], 3), // best 6, 3 runs
  (['Ab#A.#', '#.SCBE', '#.c..#', 'a.##..'], 3), // best 7, 3 runs
  (['AaSb.', 'c.#C#', 'AC.BE'], 3), // best 10, 3 runs
  (['cS#.E', '#.#..', '.ab#C', '.#.AB'], 3), // best 15, 3 runs
  (['a..Ab', '..CA#', 'ScBCE'], 3), // best 9, 3 runs
  (['E.A##', 'C#B.#', '#acS#', '..b#A'], 3), // best 10, 3 runs
  (['ECb#', 'BA#C', 'c.Sa'], 3), // best 7, 3 runs
  (['##AE', 'bS#B', '..A.', 'a.#B'], 3), // best 11, 3 runs
  (['.BCE', 'bcA.', 'SBCa'], 3), // best 8, 3 runs
  (['EC.#.', '##A.#', 'a.bc.', 'S.B..'], 3), // best 12, 3 runs
  (['#..#S#', '.bAc..', '.#C#..', 'B#E#aC'], 3), // best 11, 3 runs
  (['E.b#.', '#CBCa', '.AcAS'], 3), // best 11, 3 runs
  (['B.##.#', '..bAB.', '#a.#E.', '.S#..#'], 3), // best 10, 3 runs
  (['.#.CE', 'cSB.#', '.a.Ab'], 3), // best 8, 3 runs
  (['aCA.A', 'B.B#.', '.S#b.', 'Cc#.E'], 3), // best 13, 3 runs
  (['abS.', '..#C', 'B#EB', 'AcA#'], 3), // best 11, 3 runs
  (['EA.C', '#.B#', 'aC#.', '.bSc'], 3), // best 9, 3 runs
];
