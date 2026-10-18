/// Common, easy-to-type English words for passphrases. Written for Silicon Wallet; duplicates
/// are removed at load, and the count sets each word's entropy (`PasswordGenerator.entropy`).
enum Wordlist {
    static let words: [String] = {
        var seen = Set<String>()
        return raw.split(whereSeparator: \.isWhitespace).map(String.init).filter { seen.insert($0).inserted }
    }()

    private static let raw = """
        able about above acid acorn acre act actor adapt add adult advice aerial afar affair afford afraid
        after again agent agree ahead aid aim air airport aisle alarm album alert algae alien alive alley
        allow almond alone alpha already also alter always amber amount ample anchor angel angle animal ankle
        annual answer antler anvil apart apple apron arch arctic area arena argue arm armour army aroma
        arrow art artist ash aside ask aspect atlas atom attic audio august aunt autumn avenue avoid awake
        award away axis baby bacon badge bag bake balance balcony ball bamboo banana band bank banner barley
        barn barrel basil basin basket bat batch bath battery bay beach beacon bead beam bean bear beard
        beast beat beaver become bed bee beef beetle begin behind bell belt bench berry best better bicycle
        big bike bird birth biscuit bishop bitter black blade blanket blast blaze blend bless blind blink
        bloom blossom blue blush board boat body boil bold bolt bone bonus book boost boot border borrow
        boss bottle bounce bow bowl box brain branch brass brave bread breeze brick bridge brief bright
        bring brisk broad bronze brook broom brother brown brush bubble bucket buckle budget buffalo build
        bulb bundle bunny burden burger burrow bus bush butter button buyer buzz cabin cable cactus cage cake
        calm camel camera camp canal candle candy canoe canvas canyon cape capital captain car caravan carbon
        card cargo carpet carrot cart carve case cash castle casual cat catalog catch cattle cause cave
        cedar ceiling celery cellar cement census centre cereal chain chair chalk chance change chapel charm
        chart chase cheap check cheek cheese chef cherry chess chest chicken chief child chimney chin chip
        choice choir chorus cider cinema circle citizen city civil claim clap clay clean clerk clever cliff
        climb clinic clip clock close cloth cloud clover club clue coach coast coat cobalt cocoa coconut code
        coffee coil coin cold collar colour column comb comet comfort comic common compass concert copper
        coral core corn corner cosmic cottage cotton couch country couple course cousin cover cow crab craft
        crane crater crayon cream credit creek crew cricket crisp crop cross crowd crown cruise crumb crystal
        cube cuckoo cup cupboard curious current curtain curve cushion custom cycle daisy dance danger dark
        dash data dawn day deal dear debate decade deck decor deep deer degree delay delta demand denim
        dentist depth desert design desk detail device dial diamond diary diesel diet dinner direct dish
        divide doctor dog doll dolphin domain donkey door dot double dove dozen dragon drama draw dream dress
        drift drill drink drive drop drum duck dune dusk dust duty eager eagle early earth easel east easy
        echo eclipse edge editor effort egg eight elbow elder electric elegant element elephant elevator elk
        elm ember emerald empty enamel energy engine enjoy enough enter entry envoy equal era errand escape
        essay estate evening event exact example exit expert extra eye fabric face fact factory fairy faith
        falcon family famous fancy farm fashion fast father fault feast feather fence ferry festival fever
        fiber field fig figure film filter final finch finger fire firm first fish five flag flame flash
        flat flavour fleet flight flint float flock floor flour flower fluid flute fly foam focus fog folder
        follow food foot forest fork fortune forum fossil fountain fox frame fresh friend frog front frost
        fruit fuel funny future gadget galaxy gallery game garage garden garlic garment gate gather gauge
        gecko gem general gentle giant gift ginger giraffe glacier glad glass globe glove glow goat gold
        golf good goose gorilla gospel gossip grace grain grand grape graph grass gravel gravy great green
        grid grill grocery ground group grove guard guest guide guitar gulf habit hall hammer hamster hand
        happy harbour harp harvest hat hawk hazel head health heart hedge height helmet help herb hero heron
        hidden high hill hint history hobby hockey holiday hollow honey hood hope horizon horn horse host
        hotel hour house hover humble humour hunger husky hybrid ice icon idea igloo image impact inch index
        indigo input insect inside invite iron island item ivory ivy jacket jaguar jam jar jazz jeans jelly
        jewel job jockey join joke journey joy judge juice jungle junior jury kayak keen kettle key kidney
        kind king kiosk kitchen kite kitten kiwi knee knife knot koala label lace ladder lady lagoon lake
        lamb lamp land lane lantern laptop large laser later laugh launch lava lawn layer leader leaf learn
        leather lemon lens leopard letter level library lift light lilac lily lime limit linen lion liquid
        list little live lizard llama lobby lobster local lock lodge logic lotus loud lounge loyal lucky
        lunar lunch lyric machine magic magnet maize major mammal mango maple marble march margin market
        marsh mask master match meadow meal medal media melody melon member memory mental menu mercy merit
        metal method middle mile milk mill mineral minute mirror mist mixture model modern moment monkey
        month moon morning mosaic moss mother motion motor mountain mouse mouth movie muffin mule museum
        music mustard myth nail name napkin narrow nation nature navy near neck needle nephew nest net
        network neutral never new news next nice niece night noble noodle normal north nose note novel
        number nurse nut oak oasis oat object ocean octave october odd office olive omega onion open opera
        option orange orbit orchard orchid order organ origin orange otter outer oval oven owl oxygen oyster
        pace paddle page paint palace palm panda panel panther paper parade parcel park parrot party pass
        pasta patch path patio pause peace peach peanut pear pebble pedal pelican pen pencil penguin pepper
        perfect permit person pet phone photo piano picnic picture piece pig pigeon pillow pilot pine pink
        pioneer pipe pistachio pitch pizza place planet plant plate play plaza pledge plenty plum pocket
        poem poet point polar pole pond pony pool poppy porch port portion potato pottery powder power
        prairie praise prefer present press pretty price pride prime print prism prize prompt proof proud
        public pudding pulse pumpkin pupil puppy purple puzzle pyramid quail quarter queen quest quick quiet
        quilt quiz rabbit raccoon radar radio rain rainbow raisin ramp ranch random range rapid raven razor
        ready real reason record reef reflex region relax remote rescue resort result return reward rhythm
        ribbon rice rich riddle ridge rifle right ring ripple river road robin robot rock rocket rodeo roof
        room root rope rose rotate round route royal rubber ruby rug rugby ruler rumour rural saddle safari
        safe saga sail salad salmon salt sample sand satin sauce saucer sausage scale scarf scene school
        science scooter score scout screen script sea season seat second secret seed segment select senior
        sense series service session settle seven shadow shallow shape share shark sheep shelf shell shield
        shift shine ship shirt shoe shore short shoulder shovel shower shrimp siege signal silent silk
        silver simple singer siren sister six skate sketch ski skill sky slate sled sleep slice slide slim
        slogan slope small smart smile smoke snack snail snake snow soap soccer social sock soda sofa soft
        solar soldier solid solo song sonic soup source south space spark speak special speed sphere spice
        spider spike spin spirit splash sponge spoon sport spot spray spring sprout spruce square squash
        squid squirrel stable stadium staff stage stair stamp stand star station statue steak steam steel
        stem step stereo stick still stock stone stool storm story stove straw stream street stripe strong
        studio style subway sugar suit summer summit sun sunny sunset super supply surf surge swamp swan
        sweater sweet swift swim swing switch symbol syrup system table tablet tackle tail talent tank tape
        target task taxi tea teacher team tennis tent term test text theatre theme thing thistle thread
        three thrill thumb thunder ticket tide tiger tile timber time tiny tissue title toast today toe
        tomato tone tongue tool tooth topic torch tornado tortoise total tower town toy track tractor trade
        traffic trail train travel tray treat tree trend trial tribe trick trip trophy trout truck trumpet
        trust truth tulip tuna tunnel turkey turn turtle twelve twenty twig twin type umbrella uncle under
        unique unit universe update upper urban usual valley value valve vanilla vapour vault velvet vendor
        venue verb version vessel veteran video view village vine violet violin virtual visa visit vital
        vivid vocal voice volcano volume voyage wafer wagon waist wait walk wall walnut walrus wander warm
        wash wasp watch water wave wax way wealth weather weekend welcome well west whale wheat wheel whisper
        whistle white wide width wild willow wind window wine wing winner winter wire wisdom wise wish wizard
        wolf wonder wood wool word work world worth wrap wreath wrist writer yacht yard year yellow yoga
        yogurt young zebra zero zest zigzag zinc zone zoo
        acorn adobe alcove almanac amulet antique apricot aqua arbour archer armada artisan aster aurora
        avocado badger bagel ballad banjo bantam baroque beagle bistro bluebell bobcat bonfire bonsai
        boulder bramble breakfast brownie buckwheat bugle bungalow buttercup caramel cardinal carousel
        cashew cauldron cellist chamomile chapter chestnut chipmunk cinnamon citrus clarinet clementine
        cobble compost condor cookie cormorant cornet cosmos cowboy cranberry crocus croissant cupcake
        curry custard cypress dahlia damson dandelion dazzle denim dewdrop dingo domino doughnut dragonfly
        driftwood dumpling easter eggplant elderberry espresso fennel fern fiddle firefly fjord flamingo
        flannel fondue foxglove freckle fudge gadget gazelle geyser glimmer goblet gondola gooseberry
        granite grapefruit griffin gumdrop hammock harbor hazelnut heather hedgehog hibiscus hickory
        hummingbird iceberg iguana jasmine javelin jellyfish juniper kangaroo kestrel kingfisher lagoon
        lantern lavender lemonade lettuce licorice lighthouse limerick lobelia locket lullaby macaroon
        magnolia mallard mandolin marigold marmalade marzipan meerkat meringue minnow mistletoe mocha
        mongoose monsoon moonbeam moorland mulberry mushroom nectar nightingale nutmeg oatmeal octopus
        orbit origami ostrich paprika parsley parsnip peacock peppermint periwinkle petal pheasant pickle
        pinecone pinwheel platypus plover polka popcorn porcupine pretzel primrose puffin quartz quince
        radish raspberry redwood reindeer rhubarb rosemary saffron sage sandcastle sapphire sardine
        scallop seashell sequoia sherbet skylark snowdrop sorbet sparrow spinach starfish strawberry
        sunflower tadpole tamarind tangerine teapot thimble thyme toffee topaz toucan treacle truffle
        tumbleweed turnip twilight ukulele velour waffle walrus waterfall watermelon weasel wildflower
        windmill wombat woodpecker xylophone yarrow zeppelin
        """
}
