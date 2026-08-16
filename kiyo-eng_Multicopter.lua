local Config = ac.storage{
    debugMode = false, -- デバッグモード（物理可視化）
    droneVolume = 0.5,
    cameraAngle = 40,  -- FPVカメラ角度
    cameraFov = 110,   -- FPVカメラ視野角
    offset = 0, -- FPVカメラ前後位置オフセット
    hud = true, -- FPV用HUD

    pitchMix = 0.03,
    rollMix = 0.03,
    yawMix = 0.02,
}
local JoyStick = ac.storage{
    GUID = "",

    throttle = 1,
    throttleInvert = true,
    throttleMax = 1,
    throttleMin = 0,
    
    pitch = 4,
    pitchInvert = true,
    pitchMax = 1,
    pitchMin =-1,
    pitchExpo = 0.7,

    roll = 3,
    rollInvert = false ,
    rollMax = 1,
    rollMin = -1,
    rollExpo = 0.7,

    yaw = 0,
    yawInvert = false,
    yawMax = 1,
    yawMin = -1,
    yawExpo = 0.7,
}

local JoyStickIndex = -1

-- 読み込み用のノードを用意しておく
local dynamicRef = ac.findNodes('dynamicRoot:yes')
local droneRef = dynamicRef:createNode('DRONE',false)
local seneRef = ac.findNodes('sceneRoot:yes')

-- サウンドイベント読み込み
local soundbankLoaded = ac.loadSoundbank('./model/kiyo-eng_5inch/sfx/kiyo-eng_qc.bank', './model/kiyo-eng_5inch/sfx/GUIDs.txt')
local sound = ac.AudioEvent('event:/kiyo-eng_qc/power', true, true)

sound:setVolumeChannel(ac.AudioChannel.Main)
sound.volume = Config.droneVolume

-- ドキュメントの参照用に明示
---@class physics.RigidBody
local rigid =nil
---@class ac.SceneReference
local drone =nil
---@class ac.SceneReference
local camera =nil
---@class ac.SceneReference
local eye =nil

local cameraPos=vec3()
local camerLook=vec3()
local cameraUp=vec3()

-- カメラアングルをセット 差分だけ回した後に現在の角度を保持 
function setCameraAngle(newAngle)
    if drone then
        local diffValue = newAngle - Config.cameraAngle
        Config.cameraAngle = newAngle
        camera:rotate(vec3(1,0,0), math.rad(-diffValue))
    end
end

local motorFLPos = vec3()
local motorFRPos = vec3()
local motorRLPos = vec3()
local motorRRPos = vec3()
local properaOffset =vec3()

-- 剛体をスポーンさせる
-- ついでにドローンの初期設定をする
function addRig(pos) 
    -- すでに読み込まれているものがあったら先に削除
    if drone then drone:dispose() end 
    if rigid then rigid:setInWorld(false) end
    drone = droneRef:loadKN5({filename = './model/kiyo-eng_5inch/quad.kn5'})
    camera = drone:findNodes('maincamera')
    -- カメラの角度を設定 
    camera:rotate(vec3(1,0,0), math.rad(-Config.cameraAngle))
    eye = drone:findNodes('eye')

    -- モータの場所 ini 化するかノードから読みたいところ
    -- ノード読み出しだとずれるなぁ...
    motorFLPos = vec3(0.074,0.006,0.072)
    motorFRPos = vec3(-0.074,0.006,0.072)
    motorRLPos = vec3(0.074,0.006,-0.072)
    motorRRPos = vec3(-0.074,0.006,-0.072)
    -- プロペラの高さオフセット たぶんロールに影響する
    properaOffset = vec3(0,0.0043,0)

    -- 剛体を作成 モデルに含まれるメッシュを基に作る
    rigid = physics.RigidBody({filename = './model/kiyo-eng_5inch/quad.kn5' 
        , filter='colider'
        , debug=Config.debugMode
        , transform=true} ,0.700)
    rigid:setSemiDynamic(false,false)
    
    -- スポーン位置を車の目の前に移動
    local transform = drone:getTransformationRaw()
    local droneLook = (math.cross((ac.getCar(0).side) , vec3(0,1,0)))
    transform.position = pos
    transform.look = droneLook
    rigid:setTransformation(transform)
    
    -- 抗力の設定
    local angledamping = 0.00015 * ac.getSim().fps
    local damping = 0.000035 * ac.getSim().fps
    rigid:setDamping(damping,angledamping,true)
    rigid:setInWorld(false)

    sound:setPosition(transform.position,transform.look,transform.up,nil)
    sound:start()
end

-- 車の目の前の座標を取得する
function getPutPos()
    local car = ac.getCar(0)
    local wheels = car.wheels 
    local offset = (car.side * 0) +(car.up *1) +(car.look * 4)
    return (( wheels[0].contactPoint + wheels[1].contactPoint )/2)  + offset
end

-- FPV用のジオメトリショット
local canvas = ui.ExtraCanvas(vec2(800,600),1,render.TextureFormat.R16G16B16A16.Float)
canvas:setName('test')
local shot = ac.GeometryShot(seneRef,vec2(800,600),1,true,render.AntialiasingMode.YEBIS, render.TextureFormat.R16G16B16A16.Float)
shot:setClippingPlanes(0.01, 5e3)
shot:setBestSceneShotQuality()

function windowMain()

    -- ボタンを押すと車の前に剛体が出現する
    if ui.button('start',vec2(150,50)) then
        addRig(getPutPos())
    end
    if ac.isGamepadButtonPressed(0, ac.GamepadButton.Start) then 
        addRig(getPutPos())
    end

    if rigid then
        -- FPV
        -- メインカメラのレンズのメッシュの位置をカメラの座標とする
        -- レンズの親（カメラ基部）の座標
        ---@class mat4x4
        local cameraTF = camera:getWorldTransformationRaw()
        -- レンズの位置
        cameraPos = eye:getPosition() + vec3(0,Config.offset,0)
        camerLook = eye:getLook()
        cameraUp = eye:getUp()

        shot:update(
            cameraTF:transformPoint(cameraPos)
            ,cameraTF:transformVector(camerLook)
            ,cameraTF:transformVector(cameraUp)
            ,Config.cameraFov)
        canvas:clear()
        canvas:updateWithShader({
        textures = { tx1 = shot},
        shader = [[
        float4 main(PS_IN pin){
            float4 ret = tx1.Sample(samLinear,pin.Tex);
        return float4(ret.rgb,1);
        }]]
        })
        canvas:update(fpvHUD)


        local p1 = vec2(0,100)
        local rato = canvas:size().y/canvas:size().x
        local sizeoffset = vec2(
            ui.availableSpaceX(),
            ui.availableSpaceX()*rato
        )
        ui.drawImage(canvas,p1,p1+sizeoffset,ui.ImageFit.Stretch)
    else
        ui.dwriteDrawText("← 押すと開始 or リセット",20,vec2(200,30))
        ui.dwriteDrawText("  ※落ちたら再度飛び立てません。",20,vec2(200,55))
    end

end

-- 推力係数
local pow = 45
-- 推力
local FLFoce = 0
local FRFoce = 0
local RLFoce = 0
local RRFoce = 0
--- モータパワー
local motorFLFoce
local motorFRFoce
local motorRLFoce
local motorRRFoce

--- 対抗トルク
local FLTorq = 0 
local FRTorq = 0 
local RLTorq = 0 
local RRTorq = 0 
local motorFRtorq
local motorFLtorq
local motorRLtorq
local motorRRtorq
-- ペラ回転用のパラメータ
local maxRPS = 3000 -- 最大回転数（RPS）
local currentRPS

local tf

local rawThrottle = 0
local rawRoll = 0
local rawPitch = 0
local rawYaw = 0

local foce = 0
local roll = 0
local pitch = 0
local yaw = 0

-- 実機のExpo（感度曲線）っぽい処理
function applyExpo(val, exp)
    return math.pow(val,3) * exp + val * (1 - exp)
end

function getJoystickInput()
    rawThrottle = ac.getJoystickAxisValue(JoyStickIndex,JoyStick.throttle)*(JoyStick.throttleInvert and -1 or 1)
    rawRoll  = ac.getJoystickAxisValue(JoyStickIndex,JoyStick.roll)*(JoyStick.rollInvert and -1 or 1)
    rawPitch = ac.getJoystickAxisValue(JoyStickIndex,JoyStick.pitch)*(JoyStick.pitchInvert and -1 or 1)
    rawYaw   = ac.getJoystickAxisValue(JoyStickIndex,JoyStick.yaw)*(JoyStick.yawInvert and -1 or 1)
end

function fpvUpdate(dt)

    if rigid then
        -- 出現時に物理が有効になるようにするやつ 7割くらいは成功する
        if not rigid:isInWorld() then 
            rigid:setInWorld(true)
        end

        getJoystickInput()

        -- スロットル出力のマッピング
        foce = math.clamp(math.remap(rawThrottle, JoyStick.throttleMin, JoyStick.throttleMax, 0, 1), 0, 1)
        
        -- 感度曲線の適用
        roll  = applyExpo( math.remap(rawRoll,JoyStick.rollMin, JoyStick.rollMax,-1,1)  ,JoyStick.rollExpo)
        pitch = applyExpo( math.remap(rawPitch,JoyStick.pitchMin, JoyStick.pitchMax,-1,1)  ,JoyStick.pitchExpo)
        yaw   = applyExpo( math.remap(rawYaw,JoyStick.yawMin, JoyStick.yawMax,-1,1)  ,JoyStick.yawExpo) 


        -- 推力
        FLFoce = math.max( (foce) - (pitch * Config.pitchMix) + (roll * Config.rollMix) + ( yaw*Config.yawMix) ,0)
        FRFoce = math.max( (foce) - (pitch * Config.pitchMix) - (roll * Config.rollMix) + (-yaw*Config.yawMix) ,0)
        RLFoce = math.max( (foce) + (pitch * Config.pitchMix) + (roll * Config.rollMix) + (-yaw*Config.yawMix) ,0)
        RRFoce = math.max( (foce) + (pitch * Config.pitchMix) - (roll * Config.rollMix) + ( yaw*Config.yawMix) ,0)
        -- 対抗トルク(斜めに掛けるので0.5√2しとく)
        FLTorq = foce + (yaw*Config.yawMix) * 0.5 * math.sqrt(2)
        FRTorq = foce - (yaw*Config.yawMix) * 0.5 * math.sqrt(2)
        RLTorq = foce - (yaw*Config.yawMix) * 0.5 * math.sqrt(2)
        RRTorq = foce + (yaw*Config.yawMix) * 0.5 * math.sqrt(2)

        -- 実際の適用値へ
        -- モーターパワー
        motorFLFoce = vec3(0,(FLFoce*pow),0)
        motorFRFoce = vec3(0,(FRFoce*pow),0)
        motorRLFoce = vec3(0,(RLFoce*pow),0)
        motorRRFoce = vec3(0,(RRFoce*pow),0)
        -- トルク
        motorFLtorq = vec3((-FLTorq*pow) ,0 ,(FLTorq*pow))
        motorFRtorq = vec3(( FRTorq*pow) ,0 ,(FRTorq*pow))
        motorRLtorq = vec3((-RLTorq*pow) ,0 ,(-RLTorq*pow))
        motorRRtorq = vec3(( RRTorq*pow) ,0 ,(-RRTorq*pow))
        -- ローターごとに推力を設定
        rigid:addForce( motorFLFoce, true, motorFLPos + properaOffset, true)
        rigid:addForce( motorRLFoce, true, motorRLPos + properaOffset, true)
        rigid:addForce( motorFRFoce, true, motorFRPos + properaOffset, true)
        rigid:addForce( motorRRFoce, true, motorRRPos + properaOffset, true)
        -- 対抗トルク
        rigid:addForce(motorFLtorq , true, motorFLPos, true)
        rigid:addForce(motorFRtorq , true, motorFRPos, true)
        rigid:addForce(motorRLtorq , true, motorRLPos, true)
        rigid:addForce(motorRRtorq , true, motorRRPos, true)

        tf = rigid:getTransformation()
        
        if drone then 
            -- コライダーの動作にモデルを追従させる
            drone:setTransformationFrom(rigid)
            -- オーディオの位置を設定
            sound:setPosition(tf.position,tf.look,tf.up,rigid:getVelocity())

            -- ペラの回転（再現のみ）
            maxRPS = 3000 -- 最大回転数（RPS）
            currentRPS = maxRPS * math.max(math.log(foce+1,2)+1, 0.001)
            drone:findNodes('rotorFR'):rotate(vec3(0,0,1),math.rad( math.rad(currentRPS * FRFoce * 360 * dt)))
            drone:findNodes('rotorFL'):rotate(vec3(0,0,1),math.rad(-math.rad(currentRPS * FLFoce * 360 * dt)))
            drone:findNodes('rotorRR'):rotate(vec3(0,0,1),math.rad(-math.rad(currentRPS * RRFoce * 360 * dt)))
            drone:findNodes('rotorRL'):rotate(vec3(0,0,1),math.rad( math.rad(currentRPS * RLFoce * 360 * dt)))
            -- RPMとしてスロットルの値を設定
            sound:setParam('pow',math.lerp(0,30000,foce ))
        end
    end
end

function foceDebug()
    
    if Config.debugMode and drone then
        -- 見やすいように短くしている 
        -- 推力
        render.debugArrow(tf:transformPoint(motorFLPos + properaOffset) , tf:transformPoint((motorFLPos + properaOffset) + motorFLFoce*0.01))
        render.debugArrow(tf:transformPoint(motorFRPos + properaOffset) , tf:transformPoint((motorFRPos + properaOffset) + motorFRFoce*0.01))
        render.debugArrow(tf:transformPoint(motorRLPos + properaOffset) , tf:transformPoint((motorRLPos + properaOffset) + motorRLFoce*0.01))
        render.debugArrow(tf:transformPoint(motorRRPos + properaOffset) , tf:transformPoint((motorRRPos + properaOffset) + motorRRFoce*0.01))
        ---- トルク
        render.debugArrow(tf:transformPoint(motorFLPos + properaOffset) ,tf:transformPoint(motorFLPos + properaOffset - motorFLtorq*0.01))
        render.debugArrow(tf:transformPoint(motorFRPos + properaOffset) ,tf:transformPoint(motorFRPos + properaOffset - motorFRtorq*0.01))
        render.debugArrow(tf:transformPoint(motorRLPos + properaOffset) ,tf:transformPoint(motorRLPos + properaOffset - motorRLtorq*0.01))
        render.debugArrow(tf:transformPoint(motorRRPos + properaOffset) ,tf:transformPoint(motorRRPos + properaOffset - motorRRtorq*0.01))
    end
end



local inputLPos = vec2(320,500)
local inputRPos = vec2(480,500)
local hudColor = rgbm(1,1,1,1)
local inputRadius = 60
local thick = 3
local seg = 40
function fpvHUD()
    if rigid  and Config.hud then
        -- 速度メーター ノードの動く速度
        ui.dwriteDrawText ( string.sub("             "..string.format('%.02fkm/h',rigid:getSpeedKmh()),-12),45,vec2(530,520))
        
        -- クロスヘア
        ui.drawLine(vec2(400-20,300),vec2(400+20,300),hudColor,thick)
        ui.drawLine(vec2(400,300-20),vec2(400,300+20),hudColor,thick)

        -- 入力値表示用の十字
        ui.drawLine(vec2(inputLPos.x-inputRadius,inputLPos.y),vec2(inputLPos.x+inputRadius,inputLPos.y),hudColor,thick)
        ui.drawLine(vec2(inputRPos.x-inputRadius,inputRPos.y),vec2(inputRPos.x+inputRadius,inputRPos.y),hudColor,thick)
        ui.drawLine(vec2(inputLPos.x,inputLPos.y+inputRadius),vec2(inputLPos.x,inputLPos.y-inputRadius),hudColor,thick)
        ui.drawLine(vec2(inputRPos.x,inputRPos.y+inputRadius),vec2(inputRPos.x,inputRPos.y-inputRadius),hudColor,thick)
        
        -- 入力値表示用の円と正方形
        ui.drawRect(vec2(inputLPos.x-inputRadius,inputLPos.y-inputRadius),vec2(inputLPos.x+inputRadius,inputLPos.y+inputRadius),hudColor)
        ui.drawCircle(inputLPos,inputRadius,hudColor,seg,thick)
        ui.drawRect(vec2(inputRPos.x-inputRadius,inputRPos.y-inputRadius),vec2(inputRPos.x+inputRadius,inputRPos.y+inputRadius),hudColor)
        ui.drawCircle(inputRPos,inputRadius,hudColor,seg,thick)
        
        -- 入力値 感度カーブ補正後の物
        ui.drawCircleFilled(inputLPos + vec2(yaw*inputRadius,(math.remap(foce,1,0,-1,1)*inputRadius)),thick+5,hudColor)
        ui.drawCircleFilled(inputRPos + vec2(roll*inputRadius,(-pitch*inputRadius)),thick+5,hudColor)
    end
end


local ControllerCount = 0
local ControllerList  = {}
local AxisList = {}
function appinitialize()

    ac.debug(debugOrder().."Controller Count",ac.getJoystickCount()-1)

    repeat
        if ac.getJoystickInstanceGUID(ControllerCount) == JoyStick.GUID then
            JoyStickIndex = ControllerCount
        end
        ControllerList[ControllerCount] = ac.getJoystickName(ControllerCount).."##"..ac.getJoystickInstanceGUID(ControllerCount)
        ControllerCount = ControllerCount + 1
    until ac.getJoystickInstanceGUID(ControllerCount) == nil

    if JoyStickIndex == -1 then
        JoyStickIndex = 0
    end
    JoyStick.GUID = ac.getJoystickInstanceGUID(JoyStickIndex)

    for i = 0,ac.getJoystickAxisCount(JoyStickIndex)-1 do
        AxisList[i] = "Axis "..i
    end

    APPINITIALIZED = true
end

local function JoyStickSetting()
    local tempCursor
    local fillBar
    local barSize = vec2(224,22)
    local barOffset = vec2(130,0)
    local harfBarSize = vec2(barSize.x/2,barSize.y)
    ui.textAligned("Controller:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(300)
    JoyStickIndex , ControllerChanged= ui.combo("##JoyStickIndex",JoyStickIndex,ui.ComboFlags.HeightLargest,ControllerList)

    -- throttle
    ui.offsetCursorY(10)
    ui.textAligned("Throttle:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(100)
    JoyStick.throttle = ui.combo("##throttle",JoyStick.throttle,ui.ComboFlags.HeightLargest,AxisList)
    ui.sameLine()
    ui.textAligned("Invert:",vec2(1, 0.5),vec2(58,20))
    ui.sameLine()
    if ui.checkbox("##throttleInvert",JoyStick.throttleInvert) then JoyStick.throttleInvert = not JoyStick.throttleInvert end
    ui.textAligned("Max:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##throttleMax', JoyStick.throttleMax ,0 , 2,'%.04f')
    if changed then JoyStick.throttleMax = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y) 
    ui.textAligned("Raw:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*rawThrottle),barSize.y),rgbm.colors.white)
    ui.textAligned("Min:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##throttleMin', JoyStick.throttleMin ,-1 , 1,'%.04f')
    if changed then JoyStick.throttleMin = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    ui.textAligned("Out:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(tempCursor,tempCursor+vec2((barSize.x*foce),barSize.y),rgbm.colors.white)
    
    -- roll
    ui.newLine()
    ui.offsetCursorY(20)
    ui.textAligned("Roll:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(100)
    JoyStick.roll = ui.combo("##roll",JoyStick.roll,ui.ComboFlags.HeightLargest,AxisList)
    ui.sameLine()
    ui.textAligned("Invert:",vec2(1, 0.5),vec2(58,20))
    ui.sameLine()
    if ui.checkbox("##rollInvert",JoyStick.rollInvert) then JoyStick.rollInvert = not JoyStick.rollInvert end
    ui.textAligned("Max:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##rollMax', JoyStick.rollMax ,0 , 2,'%.04f')
    if changed then JoyStick.rollMax = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y) 
    ui.textAligned("Raw:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*rawRoll),barSize.y),rgbm.colors.white)
    ui.textAligned("Min:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##rollMin', JoyStick.rollMin ,-2 , 0,'%.04f')
    if changed then JoyStick.rollMin = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y) 
    ui.textAligned("Out:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*roll),barSize.y),rgbm.colors.white)
    ui.textAligned("Expo:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##rollExpo', JoyStick.rollExpo ,0 , 1,'%.04f')
    if changed then JoyStick.rollExpo = value end

    -- pitch
    ui.newLine()
    ui.offsetCursorY(20)
    ui.textAligned("Pitch:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(100)
    JoyStick.pitch = ui.combo("##pitch",JoyStick.pitch,ui.ComboFlags.HeightLargest,AxisList)
    ui.sameLine()
    ui.textAligned("Invert:",vec2(1, 0.5),vec2(58,20))
    ui.sameLine()
    if ui.checkbox("##pitchInvert",JoyStick.pitchInvert) then JoyStick.pitchInvert = not JoyStick.pitchInvert end
    ui.textAligned("Max:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##pitchMax', JoyStick.pitchMax ,0 , 2,'%.04f')
    if changed then JoyStick.pitchMax = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y)
    ui.textAligned("Raw:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*rawPitch),barSize.y),rgbm.colors.white)
    ui.textAligned("Min:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##pitchMin', JoyStick.pitchMin ,-2 , 0,'%.04f')
    if changed then JoyStick.pitchMin = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y)
    ui.textAligned("Out:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*pitch),barSize.y),rgbm.colors.white)
    ui.textAligned("Expo:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##pitchExpo', JoyStick.pitchExpo ,0 , 1,'%.04f')
    if changed then JoyStick.pitchExpo = value end

    --yaw
    ui.newLine()
    ui.offsetCursorY(20)
    ui.textAligned("Yaw:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(100)
    JoyStick.yaw = ui.combo("##yaw",JoyStick.yaw,ui.ComboFlags.HeightLargest,AxisList)
    ui.sameLine()
    ui.textAligned("Invert:",vec2(1, 0.5),vec2(58,20))
    ui.sameLine()
    if ui.checkbox("##yawInvert",JoyStick.yawInvert) then JoyStick.yawInvert = not JoyStick.yawInvert end
    ui.textAligned("Max:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##yawMax', JoyStick.yawMax ,0 , 2,'%.04f')
    if changed then JoyStick.yawMax = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y)
    ui.textAligned("Raw:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*rawYaw),barSize.y),rgbm.colors.white)
    ui.textAligned("Min:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##yawMin', JoyStick.yawMin ,-2 , 0,'%.04f')
    if changed then JoyStick.yawMin = value end
    ui.sameLine()
    tempCursor = ui.getCursor()+barOffset
    fillBar = vec2(tempCursor.x+harfBarSize.x,tempCursor.y)
    ui.textAligned("Out:",vec2(1, 0.5),vec2(120,20))
    ui.drawRectFilled(tempCursor ,tempCursor+barSize,rgbm.from0255(50,50,50,50))
    ui.drawRectFilled(fillBar,fillBar+vec2((harfBarSize.x*yaw),barSize.y),rgbm.colors.white)
    ui.textAligned("Expo:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##yawExpo', JoyStick.yawExpo ,0 , 1,'%.04f')
    if changed then JoyStick.yawExpo = value end

    if ControllerChanged then
        for i = 0,ac.getJoystickAxisCount(JoyStickIndex)-1 do
            AxisList[i] = "Axis "..i
        end
        JoyStick.GUID = ac.getJoystickInstanceGUID(JoyStickIndex)
    end
end

function FpvStickSetting()
    ui.offsetCursorY(10)
    ui.textAligned("Camera",vec2(1, 0.5),vec2(60,20)) 
    ui.textAligned("Angle:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##cameraAngle', Config.cameraAngle ,0 , 90,'%.01f')
    if changed then setCameraAngle(value) end

    ui.textAligned("FOV:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##Fov', Config.cameraFov ,0 , 150,'%.02f')
    if changed then Config.cameraFov = value end

    ui.textAligned("Offset:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##offset', Config.offset ,-0.3 , 0.3,'%.03f')
    if changed then Config.offset = value end

    ui.offsetCursorY(20)
    ui.textAligned("HUD",vec2(1, 0.5),vec2(60,20))
    ui.sameLine()
    ui.offsetCursorX(20)
    if ui.checkbox('###hud' , Config.hud)  then Config.hud = not Config.hud end
    
    ui.offsetCursorY(20)
    ui.textAligned("Sound",vec2(1, 0.5),vec2(60,20))
    ui.textAligned("Volume:",vec2(1, 0.5),vec2(90,20)) 
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##Volume', Config.droneVolume ,0 , 2,'%.02f')
    if changed then Config.droneVolume = value end

    ui.offsetCursorY(20)
    ui.textAligned("Sensitivity",vec2(1, 0.5),vec2(60,20))
    ui.textAligned("Pitch:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##pitch', Config.pitchMix ,0 , 0.1,'%.04f')
    if changed then Config.pitchMix = value end
    
    ui.textAligned("Roll:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##roll', Config.rollMix ,0 , 0.1,'%.04f')
    if changed then Config.rollMix = value end
    
    ui.textAligned("Yaw:",vec2(1, 0.5),vec2(90,20))
    ui.sameLine()
    ui.setNextItemWidth(250)
    local value, changed = ui.slider('##yaw', Config.yawMix ,0 , 0.1,'%.04f')
    if changed then Config.yawMix = value end

    -- ui.offsetCursorY(20)
    -- ui.textAligned("Physics",vec2(1, 0.5),vec2(60,20))
    -- ui.textAligned("Damping:",vec2(1, 0.5),vec2(90,20))
    -- ui.sameLine()
    -- ui.setNextItemWidth(250)
    -- local value, changed = ui.slider('##damping', Config.damping ,0.001 , 0.01,'%.05f')
    -- if changed then Config.damping = value end
    -- ui.sameLine()
    -- ui.text('   初期値: 0.005')
-- 
    -- ui.textAligned("AngleDamping:",vec2(1, 0.5),vec2(90,20))
    -- ui.sameLine()
    -- ui.setNextItemWidth(250)
    -- local value, changed = ui.slider('##angledamping', Config.angleDamping ,0.001 , 0.05,'%.05f')
    -- if changed then Config.angleDamping = value end
    -- ui.sameLine()
    -- ui.text('   初期値: 0.016')

    ui.offsetCursorY(20)
    ui.textAligned("Debug",vec2(1, 0.5),vec2(60,20))
    ui.sameLine()
    ui.offsetCursorX(20)
    if ui.checkbox('###devMode' , Config.debugMode)  then Config.debugMode = not Config.debugMode end

end

function setting()
    getJoystickInput()
    ui.tabBar("Settings", function()
        ui.tabItem("JoyStickSetting", JoyStickSetting)
        ui.tabItem("FPVSetting", FpvStickSetting)
    end)
end

local curOrder = 0
--- @param begin? boolean
function debugOrder(begin)
    if begin then 
        curOrder = 0
    else
        curOrder = curOrder+1
    end
    return string.sub( "00000"..curOrder,-2)..". "
end

function update()
    if not APPINITIALIZED then appinitialize() end

    -- デバッグ用
    debugOrder(true)
    ac.debug( debugOrder()..'loaded',soundbankLoaded)
    
    ac.debug(debugOrder()..'foce',foce)
    ac.debug(debugOrder()..'roll',roll)
    ac.debug(debugOrder()..'pitch',pitch)
    ac.debug(debugOrder()..'yaw',yaw)

    ac.debug(debugOrder()..'rawThrottle',rawThrottle)
    ac.debug(debugOrder()..'rawRoll',rawRoll)
    ac.debug(debugOrder()..'rawPitch',rawPitch)
    ac.debug(debugOrder()..'rawYaw',rawYaw)

    ac.debug(debugOrder()..'FLFoce',FLFoce)
    ac.debug(debugOrder()..'FRFoce',FRFoce)
    ac.debug(debugOrder()..'RLFoce',RLFoce)
    ac.debug(debugOrder()..'RRFoce',RRFoce)

    ac.debug(debugOrder()..'FLTorq',FLTorq)
    ac.debug(debugOrder()..'FRTorq',FRTorq)
    ac.debug(debugOrder()..'RLTorq',RLTorq)
    ac.debug(debugOrder()..'RRTorq',RRTorq)
    
    if rigid then 
        ac.debug(debugOrder()..'speed',rigid:getSpeedKmh())
    end
end