-- Rocket Science Periodic Table GUI
-- Place this single LocalScript in StarterPlayer > StarterPlayerScripts.
-- Creates a searchable 118-element periodic table and a details panel.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WindowManager = require(ReplicatedStorage:WaitForChild("AltheaOSWindowManager"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local osManager = WindowManager.new(playerGui)

local oldGui = playerGui:FindFirstChild("RocketPeriodicTableGUI")
if oldGui then
    oldGui:Destroy()
end

-- Data format: atomic number | symbol | name | atomic mass (u) | category | group | period | series
-- M = main table, L = lanthanides, A = actinides
local rawData = [[
1|H|Hydrogen|1.008|Reactive Nonmetal|1|1|M
2|He|Helium|4.0026|Noble Gas|18|1|M
3|Li|Lithium|6.94|Alkali Metal|1|2|M
4|Be|Beryllium|9.0122|Alkaline Earth Metal|2|2|M
5|B|Boron|10.81|Metalloid|13|2|M
6|C|Carbon|12.011|Reactive Nonmetal|14|2|M
7|N|Nitrogen|14.007|Reactive Nonmetal|15|2|M
8|O|Oxygen|15.999|Reactive Nonmetal|16|2|M
9|F|Fluorine|18.998|Halogen|17|2|M
10|Ne|Neon|20.180|Noble Gas|18|2|M
11|Na|Sodium|22.990|Alkali Metal|1|3|M
12|Mg|Magnesium|24.305|Alkaline Earth Metal|2|3|M
13|Al|Aluminum|26.982|Post-transition Metal|13|3|M
14|Si|Silicon|28.085|Metalloid|14|3|M
15|P|Phosphorus|30.974|Reactive Nonmetal|15|3|M
16|S|Sulfur|32.06|Reactive Nonmetal|16|3|M
17|Cl|Chlorine|35.45|Halogen|17|3|M
18|Ar|Argon|39.948|Noble Gas|18|3|M
19|K|Potassium|39.098|Alkali Metal|1|4|M
20|Ca|Calcium|40.078|Alkaline Earth Metal|2|4|M
21|Sc|Scandium|44.956|Transition Metal|3|4|M
22|Ti|Titanium|47.867|Transition Metal|4|4|M
23|V|Vanadium|50.942|Transition Metal|5|4|M
24|Cr|Chromium|51.996|Transition Metal|6|4|M
25|Mn|Manganese|54.938|Transition Metal|7|4|M
26|Fe|Iron|55.845|Transition Metal|8|4|M
27|Co|Cobalt|58.933|Transition Metal|9|4|M
28|Ni|Nickel|58.693|Transition Metal|10|4|M
29|Cu|Copper|63.546|Transition Metal|11|4|M
30|Zn|Zinc|65.38|Transition Metal|12|4|M
31|Ga|Gallium|69.723|Post-transition Metal|13|4|M
32|Ge|Germanium|72.630|Metalloid|14|4|M
33|As|Arsenic|74.922|Metalloid|15|4|M
34|Se|Selenium|78.971|Reactive Nonmetal|16|4|M
35|Br|Bromine|79.904|Halogen|17|4|M
36|Kr|Krypton|83.798|Noble Gas|18|4|M
37|Rb|Rubidium|85.468|Alkali Metal|1|5|M
38|Sr|Strontium|87.62|Alkaline Earth Metal|2|5|M
39|Y|Yttrium|88.906|Transition Metal|3|5|M
40|Zr|Zirconium|91.222|Transition Metal|4|5|M
41|Nb|Niobium|92.906|Transition Metal|5|5|M
42|Mo|Molybdenum|95.95|Transition Metal|6|5|M
43|Tc|Technetium|[98]|Transition Metal|7|5|M
44|Ru|Ruthenium|101.07|Transition Metal|8|5|M
45|Rh|Rhodium|102.91|Transition Metal|9|5|M
46|Pd|Palladium|106.42|Transition Metal|10|5|M
47|Ag|Silver|107.87|Transition Metal|11|5|M
48|Cd|Cadmium|112.41|Transition Metal|12|5|M
49|In|Indium|114.82|Post-transition Metal|13|5|M
50|Sn|Tin|118.71|Post-transition Metal|14|5|M
51|Sb|Antimony|121.76|Metalloid|15|5|M
52|Te|Tellurium|127.60|Metalloid|16|5|M
53|I|Iodine|126.90|Halogen|17|5|M
54|Xe|Xenon|131.29|Noble Gas|18|5|M
55|Cs|Cesium|132.91|Alkali Metal|1|6|M
56|Ba|Barium|137.33|Alkaline Earth Metal|2|6|M
57|La|Lanthanum|138.91|Lanthanide|1|8|L
58|Ce|Cerium|140.12|Lanthanide|2|8|L
59|Pr|Praseodymium|140.91|Lanthanide|3|8|L
60|Nd|Neodymium|144.24|Lanthanide|4|8|L
61|Pm|Promethium|[145]|Lanthanide|5|8|L
62|Sm|Samarium|150.36|Lanthanide|6|8|L
63|Eu|Europium|151.96|Lanthanide|7|8|L
64|Gd|Gadolinium|157.25|Lanthanide|8|8|L
65|Tb|Terbium|158.93|Lanthanide|9|8|L
66|Dy|Dysprosium|162.50|Lanthanide|10|8|L
67|Ho|Holmium|164.93|Lanthanide|11|8|L
68|Er|Erbium|167.26|Lanthanide|12|8|L
69|Tm|Thulium|168.93|Lanthanide|13|8|L
70|Yb|Ytterbium|173.05|Lanthanide|14|8|L
71|Lu|Lutetium|174.97|Lanthanide|15|8|L
72|Hf|Hafnium|178.49|Transition Metal|4|6|M
73|Ta|Tantalum|180.95|Transition Metal|5|6|M
74|W|Tungsten|183.84|Transition Metal|6|6|M
75|Re|Rhenium|186.21|Transition Metal|7|6|M
76|Os|Osmium|190.23|Transition Metal|8|6|M
77|Ir|Iridium|192.22|Transition Metal|9|6|M
78|Pt|Platinum|195.08|Transition Metal|10|6|M
79|Au|Gold|196.97|Transition Metal|11|6|M
80|Hg|Mercury|200.59|Transition Metal|12|6|M
81|Tl|Thallium|204.38|Post-transition Metal|13|6|M
82|Pb|Lead|207.2|Post-transition Metal|14|6|M
83|Bi|Bismuth|208.98|Post-transition Metal|15|6|M
84|Po|Polonium|[209]|Post-transition Metal|16|6|M
85|At|Astatine|[210]|Halogen|17|6|M
86|Rn|Radon|[222]|Noble Gas|18|6|M
87|Fr|Francium|[223]|Alkali Metal|1|7|M
88|Ra|Radium|[226]|Alkaline Earth Metal|2|7|M
89|Ac|Actinium|[227]|Actinide|1|9|A
90|Th|Thorium|232.04|Actinide|2|9|A
91|Pa|Protactinium|231.04|Actinide|3|9|A
92|U|Uranium|238.03|Actinide|4|9|A
93|Np|Neptunium|[237]|Actinide|5|9|A
94|Pu|Plutonium|[244]|Actinide|6|9|A
95|Am|Americium|[243]|Actinide|7|9|A
96|Cm|Curium|[247]|Actinide|8|9|A
97|Bk|Berkelium|[247]|Actinide|9|9|A
98|Cf|Californium|[251]|Actinide|10|9|A
99|Es|Einsteinium|[252]|Actinide|11|9|A
100|Fm|Fermium|[257]|Actinide|12|9|A
101|Md|Mendelevium|[258]|Actinide|13|9|A
102|No|Nobelium|[259]|Actinide|14|9|A
103|Lr|Lawrencium|[266]|Actinide|15|9|A
104|Rf|Rutherfordium|[267]|Transition Metal|4|7|M
105|Db|Dubnium|[268]|Transition Metal|5|7|M
106|Sg|Seaborgium|[269]|Transition Metal|6|7|M
107|Bh|Bohrium|[270]|Transition Metal|7|7|M
108|Hs|Hassium|[277]|Transition Metal|8|7|M
109|Mt|Meitnerium|[278]|Transition Metal|9|7|M
110|Ds|Darmstadtium|[281]|Transition Metal|10|7|M
111|Rg|Roentgenium|[282]|Transition Metal|11|7|M
112|Cn|Copernicium|[285]|Transition Metal|12|7|M
113|Nh|Nihonium|[286]|Post-transition Metal|13|7|M
114|Fl|Flerovium|[289]|Post-transition Metal|14|7|M
115|Mc|Moscovium|[290]|Post-transition Metal|15|7|M
116|Lv|Livermorium|[293]|Post-transition Metal|16|7|M
117|Ts|Tennessine|[294]|Halogen|17|7|M
118|Og|Oganesson|[294]|Noble Gas|18|7|M
]]

local elements = {}
local elementByNumber = {}
local elementAt = {}
for line in string.gmatch(rawData, "[^\r\n]+") do
    local fields = {}
    for field in string.gmatch(line, "[^|]+") do
        table.insert(fields, field)
    end
    if #fields == 8 then
        local e = {
            number = tonumber(fields[1]),
            symbol = fields[2],
            name = fields[3],
            mass = fields[4],
            category = fields[5],
            group = tonumber(fields[6]),
            period = tonumber(fields[7]),
            series = fields[8],
        }
        table.insert(elements, e)
        elementByNumber[e.number] = e
        if e.series == "M" then
            elementAt[tostring(e.period) .. ":" .. tostring(e.group)] = e
        end
    end
end

-- Short educational notes. Elements not listed below receive a safe, general note.
local rocketNotes = {
    H = "Hydrogen can be used as a rocket fuel. Liquid hydrogen (LH2) is commonly paired with liquid oxygen (LOX) in cryogenic rocket engines.",
    He = "Helium is an inert gas used in some launch systems for tank pressurization, purging, and ground-support operations. It is not a usual chemical rocket fuel.",
    Li = "Lithium is important in lightweight batteries and aerospace energy-storage research. Its high reactivity means it requires controlled handling.",
    B = "Boron-containing materials are researched for energetic applications and high-temperature materials, but they are not a routine main-stage rocket fuel.",
    C = "Carbon fibers and carbon-based composites can provide high stiffness at low mass for aerospace structures. The real material is usually a composite, not pure carbon alone.",
    N = "Nitrogen is used in ground systems for purging and testing. Liquid nitrogen is useful as a coolant, but it is not the same substance as liquid oxygen used as an oxidizer.",
    O = "Oxygen is a powerful oxidizer. Liquid oxygen (LOX) supports combustion with a fuel such as hydrogen or methane; oxygen itself is not the fuel in that pairing.",
    Ne = "Neon is mainly useful in specialized lighting, indicators, and research instruments rather than as a practical rocket propellant.",
    Na = "Sodium is chemically reactive and is more relevant to chemistry research and specialized materials than to ordinary rocket structures.",
    Mg = "Magnesium is a lightweight metal and appears in some pyrotechnic and materials applications. Its flammability must be considered in engineering designs.",
    Al = "Aluminum alloys offer a useful strength-to-weight balance for aerospace structures and tanks. Aluminum powder is also used in some solid propellant formulations.",
    Si = "Silicon is important in sensors, electronics, solar cells, and some ceramic materials used across aerospace systems.",
    Ar = "Argon is an inert gas used for some welding, purging, and laboratory processes. It is generally a support gas, not a conventional chemical rocket fuel.",
    Ti = "Titanium alloys combine high strength with relatively low mass and are used in selected aerospace structures and high-performance components.",
    V = "Vanadium is used in some high-strength alloys and materials research. Its value depends on the exact alloy and operating conditions.",
    Cr = "Chromium contributes corrosion resistance and high-temperature performance in many alloys and coatings.",
    Fe = "Iron is the base of steel, which can be used for ground equipment, structures, and some motor cases. It is usually heavier than aluminum or titanium for a comparable design goal.",
    Ni = "Nickel-based superalloys are valuable in hot sections of engines and turbomachinery because some retain strength at elevated temperatures.",
    Cu = "Copper's high thermal conductivity makes copper alloys useful in some regeneratively cooled rocket-engine combustion chambers and cooling channels.",
    Zn = "Zinc is used in coatings and materials chemistry; it is usually a supporting material rather than a primary rocket structure material.",
    Zr = "Zirconium compounds and alloys have specialized high-temperature and ceramic applications. The exact material formulation determines its performance.",
    Nb = "Niobium is used in selected high-temperature alloys and aerospace materials research.",
    Mo = "Molybdenum can contribute high-temperature strength in specialized components, but oxidation and operating environment matter.",
    Ag = "Silver is highly conductive and can appear in electrical contacts and specialized thermal or electronic components, but cost limits broad structural use.",
    Sn = "Tin is used in solder and coatings for electronics and electrical assemblies found in aerospace systems.",
    Xe = "Xenon is used as a propellant in some electric-propulsion systems, including ion and Hall-effect thrusters. Electric propulsion accelerates ions rather than burning fuel like a chemical engine.",
    Cs = "Cesium has specialized applications in atomic devices and research; it is not a routine rocket propellant and is highly reactive.",
    La = "Lanthanum and related rare-earth elements are used in specialized optical, electronic, catalytic, and material applications.",
    Nd = "Neodymium is used in strong permanent magnets that can be useful in motors, actuators, and other aerospace equipment.",
    Hf = "Hafnium compounds are studied for very high-temperature ceramics and thermal protection. The exact compound, not just the element, determines performance.",
    Ta = "Tantalum has corrosion-resistant and high-temperature applications in specialized components and electronics.",
    W = "Tungsten has an exceptionally high melting point and is used in some specialized high-temperature or dense components; its high density can be a disadvantage for flight mass.",
    Pt = "Platinum is used in specialized catalysts, sensors, and laboratory equipment. It is expensive and generally not used as a large structural material.",
    Au = "Gold is useful for corrosion-resistant electrical contacts and selected coatings in aerospace electronics, not as a main structural material.",
    Pb = "Lead is dense and toxic; it is generally unsuitable for many aerospace applications and requires strict controls wherever used.",
    U = "Uranium is radioactive and is not a normal chemical rocket fuel. Nuclear space-power or propulsion concepts require specialized engineering, regulation, and radiation protection.",
    Pu = "Some plutonium isotopes have been used as heat sources in radioisotope power systems for deep-space missions. This is not ordinary chemical propulsion and requires strict radiation controls.",
}

local safetyNotes = {
    H = "Highly flammable gas; liquid hydrogen is cryogenic and can cause severe cold burns. Keep away from ignition sources in any real-world context.",
    Be = "Beryllium dust and fumes are highly hazardous. This is a game encyclopedia, not a handling guide.",
    F = "Fluorine is extremely reactive and toxic.",
    Cl = "Chlorine gas is toxic and corrosive.",
    Na = "Sodium reacts strongly with water and can ignite. Do not treat the element as a casual crafting material in real life.",
    K = "Potassium reacts strongly with water and can ignite.",
    Mg = "Fine magnesium powder can burn intensely.",
    Br = "Bromine is toxic and corrosive.",
    Hg = "Mercury is toxic; exposure and environmental contamination must be avoided.",
    Pb = "Lead is toxic and can accumulate in the body.",
    Rn = "Radon is a radioactive gas and a health hazard when it accumulates indoors.",
    U = "Uranium is radioactive and chemically toxic. Real handling requires appropriate specialist controls.",
    Pu = "Plutonium is radioactive and highly controlled. Real handling requires specialist facilities and legal authorization.",
}

local categoryColors = {
    ["Alkali Metal"] = Color3.fromRGB(235, 145, 105),
    ["Alkaline Earth Metal"] = Color3.fromRGB(229, 190, 112),
    ["Transition Metal"] = Color3.fromRGB(104, 174, 220),
    ["Post-transition Metal"] = Color3.fromRGB(130, 194, 169),
    ["Metalloid"] = Color3.fromRGB(190, 159, 224),
    ["Reactive Nonmetal"] = Color3.fromRGB(112, 207, 188),
    ["Halogen"] = Color3.fromRGB(204, 151, 213),
    ["Noble Gas"] = Color3.fromRGB(127, 158, 238),
    ["Lanthanide"] = Color3.fromRGB(225, 157, 117),
    ["Actinide"] = Color3.fromRGB(211, 127, 147),
}

local function categoryColor(category)
    return categoryColors[category] or Color3.fromRGB(157, 168, 181)
end

local C = {
    bg = Color3.fromRGB(13, 18, 28),
    panel = Color3.fromRGB(20, 28, 41),
    panel2 = Color3.fromRGB(25, 35, 50),
    cell = Color3.fromRGB(24, 34, 48),
    line = Color3.fromRGB(55, 72, 91),
    text = Color3.fromRGB(238, 243, 249),
    muted = Color3.fromRGB(150, 166, 184),
    gold = Color3.fromRGB(222, 190, 126),
    cyan = Color3.fromRGB(108, 207, 222),
    warning = Color3.fromRGB(241, 157, 118),
}

local function make(className, parent, props)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function addCorner(parent, radius)
    make("UICorner", parent, { CornerRadius = UDim.new(0, radius or 8) })
end

local function addStroke(parent, color, thickness, transparency)
    return make("UIStroke", parent, {
        Color = color or C.line,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    })
end

local gui = make("ScreenGui", playerGui, {
    Name = "RocketPeriodicTableGUI",
    ResetOnSpawn = false,
    DisplayOrder = 20,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local openButton = make("TextButton", gui, {
    Name = "OpenPeriodicTableButton",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 18, 1, -118),
    Size = UDim2.fromOffset(158, 42),
    Visible = false, -- App is opened from the AltheaOS bottom dock (+).
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Text = "ELEMENT DATABASE",
    TextColor3 = C.gold,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
})
addCorner(openButton, 10)
addStroke(openButton, C.gold, 1, 0.2)

local overlay = make("Frame", gui, {
    Name = "Overlay",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(4, 7, 12),
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    Visible = false,
})

local window = make("Frame", overlay, {
    Name = "MainWindow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.97, 0, 1, -124),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
addCorner(window, 14)
addStroke(window, C.line, 1.4, 0)

local header = make("Frame", window, {
    Name = "Header",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
})

make("TextLabel", header, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(20, 8),
    Size = UDim2.new(1, -100, 0, 27),
    Text = "PERIODIC TABLE  /  ROCKET SCIENCE",
    TextColor3 = C.text,
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})
make("TextLabel", header, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(21, 35),
    Size = UDim2.new(1, -110, 0, 17),
    Text = "118 ELEMENTS  •  MATERIALS DATABASE  •  SELECT ANY ELEMENT TO EXPLORE",
    TextColor3 = C.muted,
    TextSize = 10,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local closeButton = make("TextButton", header, {
    Name = "CloseButton",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.5, 0),
    Size = UDim2.fromOffset(38, 36),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = C.text,
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
})
addCorner(closeButton, 9)
addStroke(closeButton, C.line, 1)

local searchBox = make("TextBox", window, {
    Name = "SearchBox",
    Position = UDim2.fromOffset(18, 76),
    Size = UDim2.new(0.47, -8, 0, 36),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "Search name, symbol, or atomic number...",
    PlaceholderColor3 = C.muted,
    Text = "",
    TextColor3 = C.text,
    TextSize = 13,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
})
addCorner(searchBox, 8)
addStroke(searchBox, C.line, 1)
make("UIPadding", searchBox, {
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 8),
})

local categoryNames = {
    "All", "Alkali Metal", "Alkaline Earth Metal", "Transition Metal",
    "Post-transition Metal", "Metalloid", "Reactive Nonmetal", "Halogen",
    "Noble Gas", "Lanthanide", "Actinide",
}
local selectedCategoryIndex = 1
local categoryButton = make("TextButton", window, {
    Name = "CategoryFilterButton",
    Position = UDim2.new(0.47, 4, 0, 76),
    Size = UDim2.new(0.25, -8, 0, 36),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0,
    Text = "TYPE: ALL  v",
    TextColor3 = C.gold,
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
})
addCorner(categoryButton, 8)
addStroke(categoryButton, C.line, 1)

local hintLabel = make("TextLabel", window, {
    Name = "CountLabel",
    Position = UDim2.new(0.73, 0, 0, 76),
    Size = UDim2.new(0.27, -18, 0, 36),
    BackgroundTransparency = 1,
    Text = "118 ELEMENTS",
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Right,
})

local body = make("Frame", window, {
    Name = "Body",
    Position = UDim2.fromOffset(18, 123),
    Size = UDim2.new(1, -36, 1, -140),
    BackgroundTransparency = 1,
})

local tableZone = make("Frame", body, {
    Name = "PeriodicTableZone",
    Size = UDim2.new(0.745, -8, 1, 0),
    BackgroundTransparency = 1,
})

make("TextLabel", tableZone, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(2, 0),
    Size = UDim2.new(1, -4, 0, 22),
    Text = "ELEMENT GRID  /  GROUPS 1–18",
    TextColor3 = C.muted,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local tableScroll = make("ScrollingFrame", tableZone, {
    Name = "TableScroll",
    Position = UDim2.fromOffset(0, 25),
    Size = UDim2.new(1, 0, 1, -25),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = C.cyan,
    CanvasSize = UDim2.fromOffset(940, 474),
    ScrollingDirection = Enum.ScrollingDirection.XY,
    Active = true,
})
addCorner(tableScroll, 10)
addStroke(tableScroll, C.line, 1)

local mainGrid = make("Frame", tableScroll, {
    Name = "MainElementsGrid",
    Position = UDim2.fromOffset(10, 8),
    Size = UDim2.fromOffset(940, 320),
    BackgroundTransparency = 1,
})
make("UIGridLayout", mainGrid, {
    SortOrder = Enum.SortOrder.LayoutOrder,
    FillDirection = Enum.FillDirection.Horizontal,
    FillDirectionMaxCells = 18,
    CellSize = UDim2.fromOffset(47, 42),
    CellPadding = UDim2.fromOffset(4, 4),
})

make("TextLabel", tableScroll, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(112, 330),
    Size = UDim2.fromOffset(400, 17),
    Text = "LANTHANIDES  /  57–71",
    TextColor3 = C.muted,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local lanthGrid = make("Frame", tableScroll, {
    Name = "LanthanidesGrid",
    Position = UDim2.fromOffset(112, 349),
    Size = UDim2.fromOffset(800, 44),
    BackgroundTransparency = 1,
})
make("UIGridLayout", lanthGrid, {
    SortOrder = Enum.SortOrder.LayoutOrder,
    FillDirection = Enum.FillDirection.Horizontal,
    FillDirectionMaxCells = 15,
    CellSize = UDim2.fromOffset(47, 42),
    CellPadding = UDim2.fromOffset(4, 4),
})

make("TextLabel", tableScroll, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(112, 397),
    Size = UDim2.fromOffset(400, 17),
    Text = "ACTINIDES  /  89–103",
    TextColor3 = C.muted,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local actinGrid = make("Frame", tableScroll, {
    Name = "ActinidesGrid",
    Position = UDim2.fromOffset(112, 416),
    Size = UDim2.fromOffset(800, 44),
    BackgroundTransparency = 1,
})
make("UIGridLayout", actinGrid, {
    SortOrder = Enum.SortOrder.LayoutOrder,
    FillDirection = Enum.FillDirection.Horizontal,
    FillDirectionMaxCells = 15,
    CellSize = UDim2.fromOffset(47, 42),
    CellPadding = UDim2.fromOffset(4, 4),
})

local detailPanel = make("Frame", body, {
    Name = "ElementDetailsPanel",
    Position = UDim2.new(0.755, 0, 0, 0),
    Size = UDim2.new(0.245, 0, 1, 0),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
addCorner(detailPanel, 10)
addStroke(detailPanel, C.line, 1)
make("TextLabel", detailPanel, {
    Position = UDim2.fromOffset(14, 11),
    Size = UDim2.new(1, -28, 0, 22),
    BackgroundTransparency = 1,
    Text = "ELEMENT DETAILS",
    TextColor3 = C.gold,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local detailScroll = make("ScrollingFrame", detailPanel, {
    Name = "DetailsScroll",
    Position = UDim2.fromOffset(8, 38),
    Size = UDim2.new(1, -16, 1, -46),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = C.cyan,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Active = true,
})
local infoContent = make("Frame", detailScroll, {
    Name = "InfoContent",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
})
local infoLayout = make("UIListLayout", infoContent, {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
})
make("UIPadding", infoContent, {
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 3),
    PaddingBottom = UDim.new(0, 12),
})

infoLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    detailScroll.CanvasSize = UDim2.new(0, 0, 0, infoLayout.AbsoluteContentSize.Y + 24)
end)

local elementButtons = {}
local selectedElement = nil
local currentSearch = ""
local showElement -- forward declaration used by element-button click handlers

local function makeElementButton(parent, element, order)
    local tint = categoryColor(element.category)
    local button = make("TextButton", parent, {
        Name = "Element_" .. element.symbol,
        LayoutOrder = order or element.number,
        BackgroundColor3 = C.cell,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
    })
    addCorner(button, 6)
    local stroke = addStroke(button, tint, 1, 0.08)

    local numberLabel = make("TextLabel", button, {
        Name = "AtomicNumber",
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.new(1, -6, 0, 10),
        BackgroundTransparency = 1,
        Text = tostring(element.number),
        TextColor3 = C.muted,
        TextSize = 8,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local symbolLabel = make("TextLabel", button, {
        Name = "Symbol",
        Position = UDim2.fromOffset(1, 10),
        Size = UDim2.new(1, -2, 0, 21),
        BackgroundTransparency = 1,
        Text = element.symbol,
        TextColor3 = tint,
        TextSize = 17,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local massLabel = make("TextLabel", button, {
        Name = "AtomicMass",
        Position = UDim2.new(0, 1, 1, -11),
        Size = UDim2.new(1, -2, 0, 10),
        BackgroundTransparency = 1,
        Text = element.mass,
        TextColor3 = C.muted,
        TextSize = 7,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    elementButtons[element.number] = {
        button = button,
        stroke = stroke,
        numberLabel = numberLabel,
        symbolLabel = symbolLabel,
        massLabel = massLabel,
    }
    button.Activated:Connect(function()
        if button:GetAttribute("MatchesFilter") == false then
            return
        end
        selectedElement = element
        -- Update the selected border and rebuild the details panel.
        for _, other in pairs(elementButtons) do
            other.stroke.Color = categoryColor(other.button:GetAttribute("ElementCategory") or "")
            other.stroke.Thickness = 1
        end
        stroke.Color = C.gold
        stroke.Thickness = 2
        -- showElement is assigned before the GUI becomes interactive.
        if showElement then
            showElement(element)
        end
    end)
    button:SetAttribute("ElementCategory", element.category)
    button:SetAttribute("MatchesFilter", true)
    return button
end

-- Construct all 126 positions in the main 7 x 18 block, including inert spacer cells.
for period = 1, 7 do
    for group = 1, 18 do
        local element = elementAt[tostring(period) .. ":" .. tostring(group)]
        local order = (period - 1) * 18 + group
        if element then
            makeElementButton(mainGrid, element, order)
        elseif (period == 6 or period == 7) and group == 3 then
            local placeholder = make("Frame", mainGrid, {
                Name = "SeriesPlaceholder_" .. tostring(period),
                LayoutOrder = order,
                BackgroundColor3 = C.panel2,
                BackgroundTransparency = 0.12,
                BorderSizePixel = 0,
            })
            addCorner(placeholder, 6)
            addStroke(placeholder, C.line, 1, 0.4)
            make("TextLabel", placeholder, {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = period == 6 and "57–71" or "89–103",
                TextColor3 = C.gold,
                TextSize = 10,
                Font = Enum.Font.GothamBold,
            })
        else
            make("Frame", mainGrid, {
                Name = "Empty_" .. tostring(period) .. "_" .. tostring(group),
                LayoutOrder = order,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
            })
        end
    end
end

for _, element in ipairs(elements) do
    if element.series == "L" then
        makeElementButton(lanthGrid, element, element.number)
    elseif element.series == "A" then
        makeElementButton(actinGrid, element, element.number)
    end
end

local function addInfoText(text, size, color, bold)
    return make("TextLabel", infoContent, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = text,
        TextColor3 = color or C.text,
        TextSize = size or 13,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
end

local function addDivider()
    make("Frame", infoContent, {
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = C.line,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
    })
end

local function addTag(text, color)
    local tag = make("TextLabel", infoContent, {
        Size = UDim2.new(1, -4, 0, 26),
        BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = color or C.gold,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        TextWrapped = true,
    })
    addCorner(tag, 7)
    addStroke(tag, color or C.line, 1, 0.4)
    return tag
end

showElement = function(element)
    for _, child in ipairs(infoContent:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end

    local tint = categoryColor(element.category)
    addInfoText(string.format("ELEMENT %03d  /  %s", element.number, string.upper(element.symbol)), 11, C.muted, true)
    addInfoText(element.name, 26, C.text, true)
    addInfoText(element.symbol, 38, tint, true)
    addTag(element.category, tint)
    addDivider()
    addInfoText("ATOMIC NUMBER", 10, C.muted, true)
    addInfoText(tostring(element.number) .. " protons", 16, C.text, true)
    addInfoText("For a neutral atom, the electron count equals the atomic number.", 11, C.muted, false)
    addDivider()
    addInfoText("STANDARD ATOMIC MASS", 10, C.muted, true)
    addInfoText(element.mass .. " u", 22, C.gold, true)
    addInfoText("u = unified atomic mass unit. Values for radioactive or short-lived elements may be shown as bracketed mass numbers.", 11, C.muted, false)
    addDivider()
    addInfoText("ROCKET SCIENCE APPLICATION", 10, C.cyan, true)
    addInfoText(rocketNotes[element.symbol] or "This element may be relevant to specialized materials science, electronics, sensors, chemistry, or research. Its practical use depends on the exact compound, alloy, physical state, and operating conditions; it is not necessarily a rocket propellant.", 12, C.text, false)

    local warning = safetyNotes[element.symbol]
    if warning then
        addDivider()
        addInfoText("SAFETY NOTE", 10, C.warning, true)
        addInfoText(warning, 12, C.warning, false)
    end
    addDivider()
    addInfoText("GAME DATABASE TIP", 10, C.muted, true)
    addInfoText("You can use the atomic number as a stable Resource ID in your game's inventory, crafting recipes, research tree, and global exchange market.", 11, C.muted, false)
end


local function doesMatch(element)
    local search = string.lower(currentSearch)
    local searchMatch = search == ""
        or string.find(string.lower(element.name), search, 1, true) ~= nil
        or string.find(string.lower(element.symbol), search, 1, true) ~= nil
        or string.find(tostring(element.number), search, 1, true) ~= nil
        or string.find(string.lower(element.category), search, 1, true) ~= nil
    local activeCategory = categoryNames[selectedCategoryIndex]
    local categoryMatch = activeCategory == "All" or element.category == activeCategory
    return searchMatch and categoryMatch
end

local function updateFilters()
    local matches = 0
    for _, element in ipairs(elements) do
        local refs = elementButtons[element.number]
        local matched = doesMatch(element)
        if matched then
            matches += 1
        end
        refs.button:SetAttribute("MatchesFilter", matched)
        refs.button.BackgroundTransparency = matched and 0 or 0.76
        refs.stroke.Transparency = matched and 0.08 or 0.85
        refs.numberLabel.TextColor3 = matched and C.muted or Color3.fromRGB(76, 84, 96)
        refs.symbolLabel.TextColor3 = matched and categoryColor(element.category) or Color3.fromRGB(76, 84, 96)
        refs.massLabel.TextColor3 = matched and C.muted or Color3.fromRGB(76, 84, 96)
        if element == selectedElement then
            refs.stroke.Color = C.gold
            refs.stroke.Thickness = 2
            refs.stroke.Transparency = 0
        else
            refs.stroke.Color = categoryColor(element.category)
            refs.stroke.Thickness = 1
        end
    end
    hintLabel.Text = string.format("%d / 118 ELEMENTS", matches)
    local category = categoryNames[selectedCategoryIndex]
    categoryButton.Text = category == "All" and "TYPE: ALL  v" or ("TYPE: " .. string.upper(category) .. "  v")
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    currentSearch = searchBox.Text
    updateFilters()
end)

categoryButton.Activated:Connect(function()
    selectedCategoryIndex += 1
    if selectedCategoryIndex > #categoryNames then
        selectedCategoryIndex = 1
    end
    updateFilters()
end)

-- Register Periodic Table in the shared AltheaOS window manager.
-- The manager reparents this window into its shared shell and owns close/minimize/maximize,
-- tab switching, drag/resize, modal dimming, and background blur.
osManager:RegisterWindow("Periodic Table", window, {
    Header = header,
    CloseButton = closeButton,
    Modal = true,
    BlurSize = 16,
    EscapeCloses = true,
})

openButton.Activated:Connect(function()
    updateFilters()
    osManager:OpenWindow("Periodic Table")
end)

-- Open on Hydrogen by default so players immediately see an example detail page.
selectedElement = elementByNumber[1]
showElement(selectedElement)
updateFilters()
for _, refs in pairs(elementButtons) do
    refs.stroke.Thickness = 1
end
if elementButtons[1] then
    elementButtons[1].stroke.Color = C.gold
    elementButtons[1].stroke.Thickness = 2
end
