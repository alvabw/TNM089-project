%No flahs
A = imread("./flashnoflash/puppets_01_noflash.tif");
figure
imshow(A, [],'InitialMagnification', 'fit')
title("Input Image - Camera Flash off")

%class(A)
%size(A)

%Flash
G = imread("./flashnoflash/puppets_00_flash.tif");
figure
imshow(G, [],'InitialMagnification', 'fit')
title("Guidance Image - Camera Flash On")

%class(G)
%size(G)

%info = imfinfo("./flashnoflash/puppets_01_noflash.tif"); 
%info = imfinfo("./flashnoflash/puppets_00_flash.tif"); 


%Linearization: bilder i samma linear space: Men som vi konstaterade tidigare: detta är inte en faktisk sRGB → linear RGB-konvertering.
% fast vi gör bara från 0-255 till
%0-1
flash = im2double(G);
noflash = im2double(A);

%% Guided filter: 
nhoodSize = 3;
smoothValue  = 0.001*diff(getrangefromclass(G)).^2;
B = imguidedfilter(A,G,NeighborhoodSize=nhoodSize,DegreeOfSmoothing=smoothValue);
figure
imshow(B, [],'InitialMagnification', 'fit')
title("Filtered Image")

figure
h1 = subplot(1,2,1); 
imshow(A, [],'InitialMagnification', 'fit')
title("Region in Original Image")
axis on
h2 = subplot(1,2,2); 
imshow(B, [],'InitialMagnification', 'fit')
title("Region in Filtered Image")
axis on
linkaxes([h1 h2])
xlim([520 660])
ylim([150 250])

%% flash/noflash denoising with (joint)bilaterial filters:
%Denoising av noflash: 
%Basic Bilaterial- average together pixels that are spatially near
d = 24; %SpatialSigma (σs)
r = 0.05; %DegreeOfSmoothing (ungefär σr)

filtered_noflash = imbilatfilt(noflash_small, r, d); %OBS detta knakse inte är exakt samma som i artikelns definition!

figure;
imshow(filtered_noflash, [],'InitialMagnification', 'fit');
title("Basic bilateral filter");

%% Joint bilateral - no flash filtreras, men flash används som guide för
%kanter
%Börjar testa med mindre bilderna
flash_small = imresize(flash, 0.25);
noflash_small = imresize(noflash, 0.25);
figure;
imshow(flash_small , [],'InitialMagnification', 'fit')
figure;
imshow(noflash_small , [],'InitialMagnification', 'fit')


sigma_s = 8; %24 förut men det blev tungt 
sigma_r = 0.4; %Intensitet

filtered = zeros(size(noflash_small));

radius = ceil(3*sigma_s);

[X,Y] = meshgrid(-radius:radius, -radius:radius);
spatialWeight = exp(-(X.^2 + Y.^2)/(2*sigma_s^2));

for c = 1:3

    A = noflash_small(:,:,c);
    F = flash_small(:,:,c);

    for y = 1+radius : size(A,1)-radius
        for x = 1+radius : size(A,2)-radius

            A_patch = A(y-radius:y+radius, x-radius:x+radius);
            F_patch = F(y-radius:y+radius, x-radius:x+radius);

            rangeWeight = exp(-(F_patch - F(y,x)).^2 /(2*sigma_r^2)); %Range-vikten beräknas från flash-bilden,

            weights = spatialWeight .* rangeWeight;

            weights = weights / sum(weights(:));

            filtered(y,x,c) = sum(sum(weights .* A_patch));

        end
    end
end

figure;
imshow(filtered, [],'InitialMagnification', 'fit');
title("Joint bilateral filter");

%Flash to ambient detail transfer: ---------------------
%Enkelt test: 
d = 24; %SpatialSigma (σs)
r = 0.05; %DegreeOfSmoothing (ungefär σr)

%Ratio: describes the relative local detail
epsilon = 0.02;

flash_base = imbilatfilt(flash_small, r, d);

flash_detail = (flash_small + epsilon) ./ (flash_base + epsilon);


%Lägg på no-flash bilden: multiply
% 3. Transfer flash detail to filtered ambient image
detail_strength = 1.0;

transferred = filtered .*(1 + detail_strength * (flash_detail - 1));

% 4. Keep values in valid range
transferred = min(max(transferred, 0), 1);

%Resultat innan specular o shadow masks added!!
figure;
imshow(transferred,[],'InitialMagnification', 'fit'); 
title("Flash/no-flash with detail transfer");

%% Specular mask

%Approximately linearize
flash_linear = flash_small .^ 2.2;
ambient_linear = noflash_small .^ 2.2;

%Calculate luminance: 
flash_lum = 0.2126 * flash_linear(:,:,1) + ...
            0.7152 * flash_linear(:,:,2) + ...
            0.0722 * flash_linear(:,:,3);

ambient_lum = 0.2126 * ambient_linear(:,:,1) + ...
             0.7152 * ambient_linear(:,:,2) + ...
             0.0722 * ambient_linear(:,:,3);

%Detect flash shadows---------
shadow_threshold = 0.05;
shadow_mask = abs(flash_lum - ambient_lum) <= shadow_threshold;

figure;
imshow(shadow_mask, [],'InitialMagnification', 'fit');
title("Initial Flash Shadow Mask");

%Clean the mask: morphological operations
se = strel('disk', 3);

shadow_mask = imopen(shadow_mask, se); %imopen removes small isolated regions/speckles
shadow_mask = imfill(shadow_mask, 'holes'); %imfill fills holes
shadow_mask = imdilate(shadow_mask, se);%imdilate expands the mask conservatively

figure;
imshow(shadow_mask, [],'InitialMagnification', 'fit');
title("Cleaned Flash Shadow Mask");


%Detect flash specularities: --------
specular_mask = flash_lum >= 0.95;
figure;
imshow(specular_mask,  [],'InitialMagnification', 'fit');
title("Initial Flash Specular Mask");

%clean specular
specular_mask = imopen(specular_mask, se);
specular_mask = imfill(specular_mask, 'holes');
specular_mask = imdilate(specular_mask, se);

figure;
imshow(specular_mask,   [],'InitialMagnification', 'fit');
title("Cleaned Flash Specular Mask");

%Combine the two masks:-------
M = shadow_mask | specular_mask;

figure;
imshow(M,   [],'InitialMagnification', 'fit');
title("Combined Flash Artifact Mask");

%Blurr the mask: 
M = imgaussfilt(double(M), 5);
%Now instead of just 0 or 1, the mask contains values between 0 and 1 around the boundaries.

figure;
imshow(M, [],'InitialMagnification', 'fit');
title("Final Feathered Mask");

%Använd maskerna på det vi gjorde innan: -----------------
epsilon = 0.02;

flash_base = imbilatfilt(flash_small, r, d);

flash_detail = (flash_small + epsilon) ./ (flash_base + epsilon);

%transfer
detail_strength = 1.0;

transferred = filtered .* (1 + detail_strength * (flash_detail - 1));

%Use masks
result = (1 - M) .* transferred + M .* filtered;

result = min(max(result, 0), 1);

%Display
figure;
imshow(result,[],'InitialMagnification', 'fit');
title("Flash-to-Ambient Detail Transfer");





