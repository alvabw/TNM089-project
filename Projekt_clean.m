% Struktur: 
% 1. denoising av no flash using joint bilateral filters
% 2. Specular/shadow masks
% 3.Detail transfer av flash
% 4. Add masks and result
%% Load images
%No flash
A = imread("./flashnoflash/puppets_01_noflash.tif");
figure
imshow(A, [],'InitialMagnification', 'fit')
title("Input Image - Camera Flash off")

%Flash
G = imread("./flashnoflash/puppets_00_flash.tif");
figure
imshow(G, [],'InitialMagnification', 'fit')
title("Guidance Image - Camera Flash On")

%0-255 till 0-1: 
flash = im2double(G);
noflash = im2double(A);

%% Denoising using joint bilateral av noflash
% no flash filtreras, men flash används som guide förkanter

%Börjar testa med mindre bilderna
flash_small = imresize(flash, 0.25);
noflash_small = imresize(noflash, 0.25);
% figure;
% imshow(flash_small , [],'InitialMagnification', 'fit')
% figure;
% imshow(noflash_small , [],'InitialMagnification', 'fit')


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

%% Specular/shadow masks (4.3)

%Shadow mask------------------------------------
%Approximately linearize för shadow!
flash_linear = flash_small .^ 2.2;
ambient_linear = noflash_small .^ 2.2;

%Calculate luminance: 
flash_lum = 0.2126 * flash_linear(:,:,1) + ...
            0.7152 * flash_linear(:,:,2) + ...
            0.0722 * flash_linear(:,:,3);

ambient_lum = 0.2126 * ambient_linear(:,:,1) + ...
             0.7152 * ambient_linear(:,:,2) + ...
             0.0722 * ambient_linear(:,:,3);

%Detect flash shadows
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


%Specular mask-----------------------------------------------
%Detect flash specularities
% Luminance from original flash image for specularity detection

flash_lum_original = 0.2126 * flash_small(:,:,1) + ...
                     0.7152 * flash_small(:,:,2) + ...
                     0.0722 * flash_small(:,:,3);

specular_mask = flash_lum >= 0.95;
figure;
imshow(specular_mask,  [],'InitialMagnification', 'fit');
title("Initial Flash Specular Mask");

%clean specular
se = strel('disk', 1);
%specular_mask = imopen(specular_mask, se); %Den kan ta bort alla
specular_mask = imfill(specular_mask, 'holes');
specular_mask = imdilate(specular_mask, se);

figure;
imshow(specular_mask,   [],'InitialMagnification', 'fit');
title("Cleaned Flash Specular Mask");

%Combine the two masks:------------------------------------------------
M = shadow_mask | specular_mask;

figure;
imshow(M,   [],'InitialMagnification', 'fit');
title("Combined Flash Artifact Mask");

% Blurr the mask: 
M = imgaussfilt(double(M), 5);
%Now instead of just 0 or 1, the mask contains values between 0 and 1 around the boundaries.

figure;
imshow(M, [],'InitialMagnification', 'fit');
title("Final Feathered Mask");


%% Detail trasnfer (4.2)
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

% 4. Lägg på makserna
result = (1 - M) .* transferred + M .* filtered;

result = min(max(result, 0), 1); % Keep values in valid range

figure;
imshow(result,[],'InitialMagnification', 'fit'); 
title("Flash/no-flash with detail transfer");
